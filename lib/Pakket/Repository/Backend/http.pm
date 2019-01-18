package Pakket::Repository::Backend::http;
# ABSTRACT: A remote HTTP backend repository

use Moose;
use MooseX::StrictConstructor;

use Carp              qw< croak >;
use URI::Escape       qw< uri_escape >;
use JSON::MaybeXS     qw< decode_json >;
use Path::Tiny        qw< path >;
use Log::Any          qw< $log >;
use Types::Path::Tiny qw< Path >;
use HTTP::Tiny;
use Regexp::Common    qw< URI >;
use Pakket::Utils     qw< encode_json_canonical >;
use Time::HiRes       qw< usleep >;

use constant { 'HTTP_DEFAULT_PORT' => 80 };

has 'scheme' => (
    'is'      => 'ro',
    'isa'     => 'Str',
    'default' => sub {'http'},
);

has 'host' => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
);

has 'port' => (
    'is'      => 'ro',
    'isa'     => 'Str',
    'default' => sub { HTTP_DEFAULT_PORT() },
);

has 'base_url' => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'lazy'     => 1,
    'builder'  => '_build_base_url',
);

has 'base_path' => (
    'is'      => 'ro',
    'isa'     => 'Str',
    'default' => sub {''},
);

has 'http_client' => (
    'is'      => 'ro',
    'isa'     => 'HTTP::Tiny',
    'default' => sub { HTTP::Tiny->new },
);

has 'all_object_ids' => (
    'is'      => 'ro',
    'lazy'    => 1,
    'clearer' => 'clear_all_object_ids',
    'builder' => '_build_all_object_ids',
);

with qw<
    Pakket::Role::Repository::Backend
>;

sub new_from_uri {
    my ( $class, $uri ) = @_;

    # We allow the user to not include http, because we're nice like that
    $uri !~ m{^https?://}xms
        and $uri = "http://$uri";

    $uri =~ /$RE{'URI'}{'HTTP'}{ '-scheme' => qr{https?} }{'-keep'}/xms
        or croak( $log->critical("URI '$uri' is not a proper HTTP URI") );

    # perldoc Regexp::Common::URI::http
    return $class->new(
        'scheme'    => $2,
        'host'      => $3,

        # only if matched
      ( 'port'      => $4 )x !!$4,
      ( 'base_path' => $5 )x !!$5,
    );
}

sub BUILD {
    my $self = shift;

    # check that repo exists

    # TODO: should we create dedicated endpoint to check existence of repo
    # because all_object_ids may be too heavy?
    # FIXME: If we set this to "head" instead of "get", we at least
    # don't transfer the content. -- SX
    my $url      = $self->base_url . '/all_object_ids';
    my $response = $self->http_client->get($url);
    if ( !$response->{'success'} ) {
        croak( $log->criticalf( 'Could not connect to repository %s : %d -- %s',
            $url, $response->{'status'}, $response->{'reason'} ) );
    }
}

sub _build_base_url {
    my $self = shift;

    return sprintf(
        '%s://%s:%s%s',
        $self->scheme, $self->host, $self->port, $self->base_path,
    );
}

sub _build_all_object_ids {
    my $self     = shift;
    my $url      = '/all_object_ids';
    my $full_url = $self->base_url . $url;
    my $response = $self->http_client->get($full_url);

    if ( !$response->{'success'} ) {
        croak( $log->criticalf( 'Could not get remote all_object_ids: %d -- %s',
            $response->{'status'}, $response->{'reason'} ) );
    }

    my $content = decode_json( $response->{'content'} );
    return $content->{'object_ids'};
}

sub all_object_ids_by_name {
    my ( $self, $name, $category ) = @_;
    my $response = $self->http_client->get(
        sprintf( '%s/all_object_ids_by_name?name=%s&category=%s',
            $self->base_url, uri_escape($name), uri_escape($category),
        ),
    );

    if ( !$response->{'success'} ) {
        croak( $log->criticalf( 'Could not get remote all_object_ids: %d -- %s',
            $response->{'status'}, $response->{'reason'} ) );
    }

    my $content = decode_json( $response->{'content'} );
    return $content->{'object_ids'};
}

sub has_object {
    my ( $self, $id ) = @_;
    my $response = $self->http_client->get(
        $self->base_url . '/has_object?id=' . uri_escape($id),
    );

    if ( !$response->{'success'} ) {
        croak( $log->criticalf( 'Could not get remote has_object: %d -- %s',
            $response->{'status'}, $response->{'reason'} ) );
    }

    my $content = decode_json( $response->{'content'} );
    return $content->{'has_object'};
}

sub store_location {
    my ( $self, $id, $file_to_store ) = @_;
    my $content = path($file_to_store)->slurp(
        { 'binmode' => ':raw' },
    );

    my $url      = "/store/location?id=" . uri_escape($id);
    my $full_url = $self->base_url . $url;

    my $response = $self->http_client->post(
        $full_url => {
            'content' => $content,
            'headers' => {
                'Content-Type' => 'application/x-www-form-urlencoded',
            },
        },
    );

    if ( !$response->{'success'} ) {
        croak( $log->criticalf(
            'Could not store location for id %s, URL: %s, Status: %s, Reason: %s',
            $id, $response->{'url'}, $response->{'status'}, $response->{'reason'}));
    }
}

sub retrieve_location {
    my ( $self, $id, $retries ) = @_;
    $retries //= 3;
    my $url      = '/retrieve/location?id=' . uri_escape($id);
    my $full_url = $self->base_url . $url;
    my $response = $self->http_client->get($full_url);
    if (!$response->{'success'}) {
        if ($response->{status} == 599 && $retries > 0) {
            usleep 300;
            return $self->retrieve_location($id, $retries - 1);
        }
        if ($response->{status} == 404) {
            return;
        }

        croak( $log->criticalf( 'Could not retrieve parcel %s: %s', $id, $response->{content} ) );
    }
    my $content  = $response->{'content'};
    my $location = Path::Tiny->tempfile( "$$-" . ( 'X' x 10 ) );
    $location->touch;
    $location->append( { 'binmode' => ':raw' }, $content );

    return $location;
}

sub store_content {
    my ( $self, $id, $content ) = @_;
    my $url      = "/store/content";
    my $full_url = $self->base_url . $url;

    my $response = $self->http_client->post(
        $full_url => {
            'content' => encode_json_canonical(
                { 'content' => $content, 'id' => $id, },
            ),

            'headers' => {
                'Content-Type' => 'application/json',
            },
        },
    );

    if ( !$response->{'success'} ) {
        croak( $log->criticalf( 'Could not store content for id %s', $id ) );
    }
}

sub retrieve_content {
    my ( $self, $id ) = @_;
    my $url      = '/retrieve/content?id=' . uri_escape($id);
    my $full_url = $self->base_url . $url;
    my $response = $self->http_client->get($full_url);

    if ( !$response->{'success'} ) {
        croak( $log->criticalf( 'Could not retrieve content for id %s', $id ) );
    }

    return $response->{'content'};
}

sub remove_location {
    my ( $self, $id ) = @_;
    my $url = '/remove/location?id=' . uri_escape($id);
    my $full_url = $self->base_url . $url;
    my $response = $self->http_client->get($full_url);

    if ( !$response->{'success'} ) {
        croak( $log->criticalf( 'Could not remove %s, url: %s, err: %s', $id, $response->{'url'}, $response->{'reason'}) );
    }

    return $response->{'success'};
}

sub remove_content {
    my ( $self, $id ) = @_;
    my $url = '/remove/content?id=' . uri_escape($id);
    my $full_url = $self->base_url . $url;
    my $response = $self->http_client->get($full_url);

    if ( !$response->{'success'} ) {
        croak( $log->criticalf( 'Could not remove %s, url: %s, err: %s', $id, $response->{'url'}, $response->{'reason'}) );
    }

    return $response->{'success'};
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

__END__

=pod

=head1 SYNOPSIS

    my $backend = Pakket::Repository::Backend::http->new(
        'scheme'      => 'https',
        'host'        => 'your.pakket.subdomain.company.com',
        'port'        => '80',
        'base_path'   => '/pakket/,
        'http_client' => HTTP::Tiny->new(...),
    );

    # Handling locations
    $backend->store_location( $id, $path_to_file );
    my $path_to_file = $backend->retrieve_location($id);
    $backend->remove_location($id);

    # Handling content
    $backend->store_content( $id, $structure );
    my $structure = $backend->retrieve_content($id);
    $backend->remove_content($id);

    # Getting data
    my $ids = $backend->all_object_ids; # [ ... ]
    my $ids = $backend->all_object_ids_by_name( 'Path::Tiny', 'perl' );
    if ( $backend->has_object($id) ) {
        ...
    }

=head1 DESCRIPTION

This repository backend will use HTTP to store and retrieve files and
content structures. It is useful when you are using multiple client
machines that need to either build to a remote repository or install
from a remote repository.

On the server side you will need to use L<Pakket::Web>.

=head1 ATTRIBUTES

When creating a new class, you can provide the following attributes:

=head2 scheme

The scheme to use.

Default: B<https>.

=head2 host

Hostname or IP string to use.    

This is a required parameter.

=head2 port

The port on which the remote server is listening.

Default: B<80>.

=head2 base_path

The default path to prepend to the request URL. This is useful when you
serve it on a server that also serves other content, or when you have
multiple pakket instances and they are in subdirectories.

Default: empty.

=head2 base_url

This is an advanced attribute that is generated automatically from the
C<host>, C<port>, and C<base_path>. This uses B<http> by default but
you can create your own with B<https>:

    my $backend = Pakket::Repository::Backend::http->new(
        'base_path' => 'https://my.path:80/secure_packages/',
    );

Default: B<<C<http://HOST:PORT/BASE_URL>>>.

=head2 http_client

This is an advanced attribute defining the user agent to be used for
fetching or updating data. This uses L<HTTP::Tiny> so you need one that
is compatible or a subclass of it.

Default: L<HTTP::Tiny> object.

=head1 METHODS

All examples below use a particular string as the ID, but the ID could
be anything you wish. Pakket uses the package ID for it, which consists
of the category, name, version, and release.

=head2 store_location

    $backend->store_location(
        'perl/Path::Tiny=0.100:1',
        '/tmp/myfile.tar.gz',
    );

This method makes a request to the server in the path
C</store/location?id=$ID>. The C<$ID> is URI-escaped and the request
is made as a C<x-www-form-urlencoded> request.

The request is guarded by a check that will report this error, making
the return value is useless.

=head2 retrieve_location 

    my $path = $backend->retrieve_location('perl/Path::Tiny=0.100:1');

This method makes a request to the server in the path
C</retrieve/location?id=$ID>. The C<$ID> is URI-escaped.

A temporary file is then created with the content and the method
returns the location of this file.

=head2 remove_location

    $backend->remove_location('perl/Path::Tiny=0.100:1');

This method makes a request to the server in the path
C</remove/location?id=$ID>. The C<$ID> is URI-escaped.

The return value is a boolean of the success or fail of this operation.

=head2 store_content

    $backend->store_content(
        'perl/Path::Tiny=0.100:1',
        {
            'Package' => {
                'category' => 'perl',
                'name'     => 'Path::Tiny',
                'version'  => 0.100,
                'release'  => 1,
            },

            'Prereqs' => {...},
        },
    );

This method makes a POST request to the server in the path
C</store/content>. The request body contains the content, encoded
into JSON. This means you cannot store objects, only plain structures.

The request is guarded by a check that will report this error, making
the return value is useless. To retrieve the content, use
C<retrieve_content> described below.

=head2 retrieve_content

    my $struct = $backend->retrieve_content('perl/Path::Tiny=0.100:1');

This method makes a request to the server in the path
C</retrieve/content?id=$ID>. The C<$ID> is URI-escaped.

It then returns the content as a structure, unserialized.

=head2 remove_content

    my $success = $backend->remove_content('perl/Path::Tiny=0.100:1');

This method makes a request to the server in the path
C</remove/content?id=$ID>. The C<$ID> is URI-escaped.

The return value is a boolean of the success or fail of this operation.

=head2 all_object_ids

    my $ids = $backend->all_object_ids();

This method makes a request to the server in the path
C</all_object_ids> and returns all the IDs of objects it stores in an
array reference. This helps find whether an object is available or not.

=head2 all_object_ids_by_name

    my $ids = $backend->all_object_ids_by_name( $name, $category );

This is a more specialized method that receives a name and category for
a package and locates all matching IDs.

This method makes a request to the server in the path
C</all_object_ids_by_name?name=$NAME&category=$CATEGORY>. The
C<$NAME> and C<$CATEGORY> are URI-escaped.

It then returns all the IDs it finds in an array reference.

You do not normally need to use this method.

=head2 has_object

    my $exists = $backend->has_object('perl/Path::Tiny=0.100:1');

This method receives an ID and returns a boolean if it's available.

This method makes a request to the server in the path
C</has_object?id=$ID>. The C<$ID> is URI-escaped.

package Pakket::Repository::Backend::Http;

# ABSTRACT: A remote HTTP backend repository

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

# core
use Carp;
use experimental qw(declared_refs refaliasing signatures);

# non core
use Log::Any qw($log);
use Mojo::URL;
use Mojo::UserAgent;
use Path::Tiny;

# local
use Pakket::Utils qw(encode_json_one_line);

use constant {
    'HTTP_DEFAULT_PORT' => 80,
    'HTTP_TIMEOUT'      => 599,
    'SLEEP_TIMEOUT'     => 300,
};

has 'url' => (
    'is'       => 'ro',
    'isa'      => 'Mojo::URL',
    'required' => 1,
);

has 'file_extension' => (
    'is'      => 'ro',
    'isa'     => 'Str',
    'default' => 'tgz',
);

has '_UA' => (
    'is'      => 'ro',
    'isa'     => 'Mojo::UserAgent',
    'default' => sub {Mojo::UserAgent->new},
);

with qw(
    Pakket::Role::Repository::Backend
);

sub new_from_uri ($class, $uri) {
    my $url = Mojo::URL->new($uri);
    $log->debugf('%s: %s', (caller (0))[3], $uri);

    my %params = ('url' => $url);
    $log->debugf('%s params: %s', (caller (0))[3], encode_json_one_line(\%params));

    return $class->new(\%params);
}

sub BUILDARGS ($class, $args) {
    my ($url, $file_extension);
    if ($args->{'url'}) {
        $url            = Mojo::URL->new($args->{'url'});
        $file_extension = $url->query->param('file_extension');
        $url->path($url->path . '/') if substr ($url->path, -1, 1) ne '/';
        $url->query('');
    } else {
        croak $log->criticalf('Invalid params, host is required: %s', encode_json_one_line($args)) if !$args->{'host'};
        $file_extension = $args->{'file_extension'};
        $url            = Mojo::URL->new;
        $url->host($args->{'host'});
        $url->scheme($args->{'scheme'} // 'https');
        $url->port($args->{'port'})      if $args->{'port'};
        $url->path($args->{'base_path'}) if $args->{'base_path'};
        $url->path($url->path . '/')     if substr ($url->path, -1, 1) ne '/';
    }

    $url->is_abs
        or croak($log->criticalf('invalid URL: %s', $url));

    return {
        'url'            => $url,
        'file_extension' => $file_extension,
    };
}

sub BUILD ($self, @) {
    $self->{'file_extension'} eq ''                                            # add one dot if necessary
        or $self->{'file_extension'} =~ s{^(?:[.]*)(.*)}{.$1}x;

    return;
}

sub all_object_ids ($self) {
    my $url = $self->url->clone->path('all_object_ids');
    $log->debugf('%s url: %s', (caller (0))[3], $url);

    my $res = $self->_UA->get($url => {'Accept' => 'application/json'})->result;
    if ($res->is_error) {
        croak $log->criticalf('Could not fetch from "%s": %s %s %s', $url, $res->code, $res->message, $res->body);
    }

    return $res->json->{'object_ids'};
}

sub all_object_ids_by_name ($self, $category, $name) {
    my $url = $self->url->clone->path('all_object_ids_by_name')->query(
        'category' => $category,
        'name'     => $name,
    );
    $log->debugf('%s url: %s', (caller (0))[3], $url);

    my $res = $self->_UA->get($url => {'Accept' => 'application/json'})->result;
    if ($res->is_error) {
        croak $log->criticalf('Could not fetch from "%s": %s %s %s', $url, $res->code, $res->message, $res->body);
    }

    my \@object_ids = $res->json->{'object_ids'};
    return \@object_ids;
}

sub has_object ($self, $id) {
    my $url = $self->url->clone->path('has_object')->query('id' => $id);
    $log->debugf('%s url: %s', (caller (0))[3], $url);

    my $res = $self->_UA->get($url => {'Accept' => 'application/json'})->result;
    if ($res->is_error) {
        croak $log->criticalf('Could not fetch from "%s": %s %s %s', $url, $res->code, $res->message, $res->body);
    }

    return int !!$res->json->{'has_object'};
}

sub remove ($self, $id) {
    my $url = $self->url->clone->path('remove/location')->query('id' => $id);
    $log->debugf('%s url: %s', (caller (0))[3], $url);

    my $res = $self->_UA->get($url => {'Accept' => 'application/json'})->result;
    if ($res->is_error) {
        croak $log->criticalf('Could not remove from "%s": %s %s', $url, $res->code, $res->message);
    }

    return $res->json->{'success'};
}

sub retrieve_content ($self, $id, $retries = 3) {
    my $url = $self->url->clone->path('retrieve/content')->query('id' => $id);
    $log->debugf('%s url: %s', (caller (0))[3], $url);

    my $res = $self->_UA->get($url => {'Accept' => 'application/json'})->result;
    if ($res->is_error) {
        croak $log->criticalf('Could not fetch from "%s": %s %s', $url, $res->code, $res->message);
    }

    return $res->body;
}

sub retrieve_location ($self, $id, $retries = 3) {
    my $url = $self->url->clone->path('retrieve/location')->query('id' => $id);
    $log->debugf('%s url: %s', (caller (0))[3], $url);

    my $res = $self->_UA->get($url => {'Accept' => 'application/octet-stream'})->result;
    if ($res->is_error) {
        croak $log->criticalf('Could not fetch from "%s": %s %s', $url, $res->code, $res->message);
    }

    my $location = Path::Tiny->tempfile('X' x 10);

    $location->spew_raw($res->body);

    return $location;
}

sub store_content ($self, $id, $content) {
    my $url = $self->url->clone->path('store/content');
    $log->debugf('%s url: %s', (caller (0))[3], $url);

    my $res = $self->_UA->post(
        $url => {
            'Accept' => 'application/json',
        },
        'json' => {
            'content' => $content,
            'id'      => $id,
        },
    )->result;

    if ($res->is_error) {
        croak $log->criticalf('Could not store content to "%s": %s %s', $url, $res->code, $res->message);
    }

    return;
}

sub store_location ($self, $id, $file_to_store) {
    my $content = path($file_to_store)->slurp_raw;
    my $url     = $self->url->clone->path('store/location')->query('id' => $id);
    $log->debugf('%s url: %s', (caller (0))[3], $url);

    my $res = $self->_UA->post(
        $url => {
            'Accept' => 'application/json',
        },
        $content,
    )->result;

    if ($res->is_error) {
        croak $log->criticalf('Could not store location to "%s": %s %s', $url, $res->code, $res->message);
    }

    return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 SYNOPSIS

    my $id      = 'perl/Pakket=0:1';
    my $backend = Pakket::Repository::Backend::Http->new(
        'scheme'      => 'https',
        'host'        => 'your.pakket.subdomain.company.com',
        'port'        => '80',
        'base_path'   => '/pakket/',
        'http_client' => HTTP::Tiny->new(),
    );

    # Handling locations
    $backend->store_location( $id, 'path/to/file' );
    my $path_to_file = $backend->retrieve_location($id);
    $backend->remove($id);

    # Handling content
    $backend->store_content( $id, 'structured_data' );
    my $structure = $backend->retrieve_content($id);

    # Getting data
    #my $ids = $backend->all_object_ids; # [ ... ]
    my $ids = $backend->all_object_ids_by_name('perl', 'Path::Tiny');
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

    my $backend = Pakket::Repository::Backend::Http->new(
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

=head2 remove

    $backend->remove('perl/Path::Tiny=0.100:1');

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
            }
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

=head2 all_object_ids

    my $ids = $backend->all_object_ids();

This method makes a request to the server in the path
C</all_object_ids> and returns all the IDs of objects it stores in an
array reference. This helps find whether an object is available or not.

=head2 all_object_ids_by_name

    my $ids = $backend->all_object_ids_by_name($category, $name);

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

=cut

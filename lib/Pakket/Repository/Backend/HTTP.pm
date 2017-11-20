package Pakket::Repository::Backend::HTTP;
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
use Pakket::Utils     qw< encode_json_canonical >;

with qw<
    Pakket::Role::Repository::Backend
>;

has 'host' => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
);

has 'port' => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
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
    'is'       => 'ro',
    'isa'      => 'HTTP::Tiny',
    'default'  => sub { HTTP::Tiny->new },
);


sub BUILD {
    my $self = shift;

    # check that repo exists

    # TODO: should we create dedicated endpoint to check existence of repo
    # because all_object_ids may be too heavy?
    my $url = $self->base_url . '/all_object_ids';
    my $response = $self->http_client->get($url);
    if ( !$response->{'success'} ) {
        croak( $log->criticalf( 'Could not connect to repository %s : %d -- %s',
            $url, $response->{'status'}, $response->{'reason'} ) );
    }
}

sub _build_base_url {
    my $self = shift;
    return sprintf(
        'http://%s:%s%s', $self->host, $self->port, $self->base_path,
    );
}

sub all_object_ids {
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
        )
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

    my $url = "/store/location?id=" . uri_escape($id);
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
    my ( $self, $id ) = @_;
    my $url      = '/retrieve/location?id=' . uri_escape($id);
    my $full_url = $self->base_url . $url;
    my $response = $self->http_client->get($full_url);
    $response->{'success'} or return;
    my $content  = $response->{'content'};
    my $location = Path::Tiny->tempfile;
    $location->spew( { 'binmode' => ':raw' }, $content );
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
    return $response->{'success'};
}

sub remove_content {
    my ( $self, $id ) = @_;
    my $url = '/remove/content?id=' . uri_escape($id);
    my $full_url = $self->base_url . $url;
    my $response = $self->http_client->get($full_url);
    return $response->{'success'};
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

__END__

=pod

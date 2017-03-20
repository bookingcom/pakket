package Pakket::Repository::Backend::HTTP;
# ABSTRACT: A remote HTTP backend repository

# FIXME: Add methods: remove_location remove_content

use Moose;
use MooseX::StrictConstructor;

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
        die $log->criticalf( 'Could not get remote all_object_ids: %d -- %s',
            $response->{'status'}, $response->{'reason'} );
    }

    my $content = decode_json( $response->{'content'} );
    return $content->{'data'};
}

sub has_object {
    my ( $self, $id ) = @_;
    my $response = $self->http_client->get(
        $self->base_url . '/has_object?id=' . uri_escape($id),
    );

    if ( !$response->{'success'} ) {
        die $log->criticalf( 'Could not get remote has_object: %d -- %s',
            $response->{'status'}, $response->{'reason'} );
    }

    my $content = decode_json( $response->{'content'} );
    return $content->{'has_object'};
}

sub store_location {
    my ( $self, $id, $file_to_store ) = @_;
    my $content = {
        'data' => path($file_to_store)->slurp( { 'binmode' => ':raw' } ),
    };
    $self->store_content( $id, $content );
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
            'content' => encode_json_canonical( { 'data' => $content, 'id' => $id, } ),
            'headers' => {
                'Content-Type' => 'application/json',
            },
        },
    );

    if ( !$response->{'success'} ) {
        die $log->criticalf( 'Could not store content for id %s', $id );
    }
}

sub retrieve_content {
    my ( $self, $id ) = @_;
    my $url      = '/retrieve/content?id=' . uri_escape($id);
    my $full_url = $self->base_url . $url;
    my $response = $self->http_client->get($full_url);

    if ( !$response->{'success'} ) {
        die $log->criticalf( 'Could not retrieve content for id %s', $id );
    }

    return $response->{'content'};
}

# FIXME: Add these
sub remove_content;
sub remove_location;

__PACKAGE__->meta->make_immutable;
no Moose;

1;

__END__

=pod

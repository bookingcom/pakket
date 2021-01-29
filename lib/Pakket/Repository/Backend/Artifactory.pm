package Pakket::Repository::Backend::Artifactory;

# ABSTRACT: An Artifactory repository backend

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

# core
use Carp;
use Digest::SHA qw(sha1_hex);
use experimental qw(declared_refs refaliasing signatures);

# non core
use HTTP::Tiny;
use JSON::MaybeXS;
use Log::Any qw($log);
use Path::Tiny;

# local
use Pakket::Utils::Package qw(
    parse_package_id
);

use constant {
    'INDEX_UPDATE_INTERVAL_SEC' => 60 * 5,
    'DEFAULT_CATEGORIES'        => [qw(perl native)],
};

has 'url' => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
);

has 'path' => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
);

has 'api_key' => (
    'is'      => 'ro',
    'isa'     => 'Str',
    'default' => sub {$ENV{'JFROG_ARTIFACTORY_API_KEY'} || ''},
);

has 'file_extension' => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
);

has '_client' => (
    'is'      => 'ro',
    'isa'     => 'HTTP::Tiny',
    'lazy'    => 1,
    'builder' => '_build_client',
);

with qw(
    Pakket::Role::Repository::Backend
);

sub new_from_uri ($class, $uri) {
    croak($log->criticalf('new_from_uri: impossible to use with:', $class));
}

sub BUILD ($self, @) {
    $self->{'file_extension'} =~ s{^[.]+}{}x;

    return;
}

sub all_object_ids ($self) {
    my \%index = $self->_index;

    my @all_object_ids = keys %index;

    return \@all_object_ids;
}

sub all_object_ids_by_name ($self, $category, $name) {
    my \%index = $self->_index;

    my @object_ids = grep {my ($c, $n) = parse_package_id($_); $c eq $category and $n eq $name} keys %index;

    return \@object_ids;
}

sub has_object ($self, $id) {
    my \%index = $self->_index;

    exists $index{$id}
        or \%index = $self->_index(1);

    return exists $index{$id};
}

sub remove ($self, $id) {
    state $base_url = join ('/', $self->url, $self->path);
    my $uri = join ('.', $id,       $self->file_extension);
    my $url = join ('/', $base_url, $uri);

    my $response = $self->_client->delete($url);
    $response->{'success'}
        or croak($log->criticalf('Could not remove %s: [%d] %s', $url, $response->@{qw(status reason)}));

    my \%index = $self->_index;
    delete $index{$id};

    return 1;
}

sub retrieve_content ($self, $id) {
    state $base_url = join ('/', $self->url, $self->path);
    my $uri = join ('.', $id,       $self->file_extension);
    my $url = join ('/', $base_url, $uri);

    my $response = $self->_client->get($url);
    $response->{'success'}
        or croak($log->criticalf('Could not retrieve content of %s: [%d] %s', $url, $response->@{qw(status reason)}));

    return $response->{'content'};
}

sub retrieve_location ($self, $id) {
    my $location = Path::Tiny->tempfile('pakket-' . ('X' x 10));
    $location->spew_raw($self->retrieve_content($id));

    return $location;
}

sub store_content ($self, $id, $content) {
    state $base_url = join ('/', $self->url, $self->path);
    my $uri = join ('.', $id,       $self->file_extension);
    my $url = join ('/', $base_url, $uri);

    my $sha1     = sha1_hex($content);
    my $response = $self->_client->put(
        $url,
        {
            'content' => $content,
            'headers' => {
                'X-Checksum-Deploy' => 'false',
                'X-Checksum-Sha1'   => $sha1,
            },
        },
    );
    $response->{'success'}
        or croak($log->criticalf('Could not store content of %s: [%d] %s', $url, $response->@{qw(status reason)}));

    my \%index = $self->_index;
    $index{$id} = {'sha1' => $sha1};

    return;
}

sub store_location ($self, $id, $file_to_store) {
    return $self->store_content($id, path($file_to_store)->slurp);
}

sub _index ($self, $force_update = 0) {
    state $base_url    = join ('/', $self->url, 'api/storage', $self->path);
    state $update_time = 0;
    state $index_cache = {};

    if (time - INDEX_UPDATE_INTERVAL_SEC < $update_time && !$force_update) {
        return $index_cache;
    }

    my \%index = $index_cache;
    %index = ();
    if ($self->api_key) {
        state $regex = qr{\A [/] (.*) [.] $self->{file_extension}\z}x;
        my $response = $self->_client->get(join ('?', $base_url, 'list&deep=1'));

        # if we have api_key use more powerful api, this will give us sha1 of the items for free
        if (!$response->{'success'}) {
            croak($log->criticalf('Could not list repository %s: [%d] %s', $base_url, $response->@{qw(status reason)}));
        }

        foreach my $it (decode_json($response->{'content'})->{'files'}->@*) {
            my ($name) = $it->{'uri'} =~ $regex;
            $index{$name} = $it;
        }
    } else {
        state $regex = qr{\A (.*) [.] $self->{file_extension}\z}x;
        foreach my $category (DEFAULT_CATEGORIES()->@*) {
            my $response = $self->_client->get(join ('/', $base_url, $category));

            if (!$response->{'success'}) {
                croak(
                    $log->criticalf(
                        'Could not list repository %s: [%d] %s',
                        $base_url, $response->@{qw(status reason)},
                    ),
                );
            }

            foreach my $it (decode_json($response->{'content'})->{'children'}->@*) {
                my ($name) = $it->{'uri'} =~ $regex;
                undef $index{$category . $name};
            }
        }
    }

    $update_time = time;
    return \%index;
}

sub _build_client ($self) {
    my %default_headers;
    $default_headers{'X-JFrog-Art-Api'} = $self->api_key if $self->api_key;

    return HTTP::Tiny->new(
        default_headers => \%default_headers,
    );
}

__PACKAGE__->meta->make_immutable;

1;

__END__

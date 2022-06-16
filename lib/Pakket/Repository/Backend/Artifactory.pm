package Pakket::Repository::Backend::Artifactory;

# ABSTRACT: An Artifactory repository backend

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

# core
use Carp;
use Digest::SHA  qw(sha1_hex);
use experimental qw(declared_refs refaliasing signatures);

# non core
use JSON::MaybeXS;
use Log::Any qw($log);
use Mojo::URL;
use Mojo::Path;
use Path::Tiny;

# local
use Pakket::Utils          qw(encode_json_one_line);
use Pakket::Utils::Package qw(
    parse_package_id
);

use constant {
    'CACHE_TTL'          => 60 * 5,
    'DEFAULT_CATEGORIES' => [qw(perl native)],
};

has 'url' => (
    'is'       => 'ro',
    'isa'      => 'Mojo::URL',
    'required' => 1,
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

with qw(
    Pakket::Role::HttpAgent
    Pakket::Role::Repository::Backend
);

sub new_from_uri ($class, $uri) {
    my $url = Mojo::URL->new($uri);

    $url->is_abs
        or croak($log->criticalf('invalid URL: %s', $url->to_string));

    my $query  = $url->query;
    my %params = (
        'path' => $url->path->to_string,
        ('url'            => $query->param('url')) x !!defined $query->param('url'),
        ('api_key'        => $query->param('api_key')) x !!defined $query->param('api_key'),
        ('file_extension' => $query->param('file_extension')) x !!defined $query->param('file_extension'),
        ('validate_id'    => $query->param('validate_id')) x !!defined $query->param('validate_id'),
    );

    return $class->new(\%params);
}

sub BUILDARGS ($class, @params) {
    my %args;
    if (@params == 1) {
        \%args = $params[0];
    } else {
        %args = @params;
    }

    if ($args{'url'} && $args{'path'}) {
        my $url  = Mojo::URL->new($args{'url'});
        my $path = Mojo::Path->new($args{'path'})->leading_slash(0)->trailing_slash(1);
        $url->path->trailing_slash(1);

        $url->is_abs
            or croak($log->criticalf('invalid URL: %s', $url));

        $args{'url'}  = $url;
        $args{'path'} = $path->to_string;
    }

    return {
        'path' => $args{'path'},
        'url'  => $args{'url'},
        ('api_key'        => $args{'api_key'}) x !!$args{'api_key'},
        ('file_extension' => $args{'file_extension'}) x !!defined $args{'file_extension'},
        ('validate_id'    => $args{'validate_id'}) x !!defined $args{'validate_id'},
    };
}

sub BUILD ($self, @) {
    $self->{'file_extension'} eq ''                                            # add one dot if necessary
        or $self->{'file_extension'} =~ s{^(?:[.]*)(.*)}{.$1}x;

    return;
}

sub all_object_ids ($self) {

    #     $log->debugf('%s: %s', (caller (0))[3], $self->path);
    my \%index = $self->index;
    my @all_object_ids = keys %index;
    return \@all_object_ids;
}

sub all_object_ids_by_name ($self, $category, $name) {

    #     $log->debugf('%s: %s %s/%s', (caller (0))[3], $self->path, $category, $name);

    my \%index = $self->index;
    my @all_object_ids = keys %index;

    my @all_object_ids_by_name
        = grep {my ($c, $n) = parse_package_id($_); (!$category || !$c || $c eq $category) && $n eq $name}
        @all_object_ids;

    return \@all_object_ids_by_name;
}

sub has_object ($self, $id) {

    #     $log->debugf('%s: %s %s', (caller (0))[3], $self->path, $id);
    my \%index = $self->index;
    return exists $index{$id};
}

sub remove ($self, $id) {

    #     $log->debugf('%s: %s %s', (caller (0))[3], $self->path, $id);
    my \%index = $self->index;

    $index{$id}
        or return;

    my $url = $self->url->clone->path($self->path)->path($id . $self->file_extension);

    $self->http_delete(
        $url => {
            'X-JFrog-Art-Api' => $self->api_key,
        },
    );

    delete $index{$id};
    return 1;
}

sub retrieve_content ($self, $id) {

    #     $log->debugf('%s: %s %s', (caller (0))[3], $self->path, $id);
    my $rel = $self->index->{$id}
        or croak($log->criticalf('Not found: %s', $id));

    my $url = $self->url->clone->path($self->path)->path($id . $self->file_extension);

    my $res = $self->http_get($url)->result;
    return $res->body;
}

sub retrieve_location ($self, $id) {

    #     $log->debugf('%s: %s %s', (caller (0))[3], $self->path, $id);
    my $tmp = Path::Tiny->tempfile('pakket-' . ('X' x 10));
    $tmp->spew_raw($self->retrieve_content($id));

    return $tmp;
}

sub store_content ($self, $id, $content) {

    #     $log->debugf('%s: %s %s', (caller (0))[3], $self->path, $id);
    $self->check_id($id);

    my $url  = $self->url->clone->path($self->path)->path($id . $self->file_extension);
    my $sha1 = sha1_hex($content);

    my \%index = $self->index;

    if ($index{$id}) {
        if ($index{$id}{'sha1'} eq $sha1) {
            $log->noticef('Skipping as sha1 matches the upstream data for: %s', $id);
            return;
        } else {
            $log->warnf('Owerwriting: %s', $id);
        }
    }

    $self->http_put(
        $url => {
            'X-Checksum-Deploy' => 'false',
            'X-Checksum-Sha1'   => $sha1,
            'X-JFrog-Art-Api'   => $self->api_key,
        },
        $content,
    );

    $index{$id}{'sha1'} = $sha1;

    return;
}

sub store_location ($self, $id, $file_to_store) {

    #     $log->debugf('%s: %s %s', (caller (0))[3], $self->path, $id);
    return $self->store_content($id, path($file_to_store)->slurp_raw);
}

sub index ($self, $force_update = 0) { ## no critic [Subroutines::ProhibitBuiltinHomonyms]
    $self->clear_index if $force_update;

    my $cache_name = $self->url . $self->path;
    my \%result = $self->_cache->compute(
        __PACKAGE__ . $cache_name,
        CACHE_TTL(),
        sub {
            my %by_id;

            my $base_url = $self->url->clone->path('api/storage/')->path($self->path);

            # if we have api_key use more powerful api, this will give us sha1 of the items for free
            if ($self->api_key) {
                my $regex = qr{\A [/] (.*) $self->{file_extension}\z}x;
                my $res   = $self->http_get(
                    join ('?', $base_url, 'list&deep=1') => {
                        'X-JFrog-Art-Api' => $self->api_key,
                    },
                )->result;

                foreach my $it ($res->json->{'files'}->@*) {
                    my ($id) = $it->{'uri'} =~ $regex;
                    $by_id{$id} = $it;
                }
            } else {
                my $regex = qr{\A (.*) $self->{file_extension}\z}x;

                foreach my $category (DEFAULT_CATEGORIES()->@*) {
                    my $res = $self->http_get($base_url->clone->path($category))->result;

                    foreach my $it ($res->json->{'children'}->@*) {
                        my ($id) = $it->{'uri'} =~ $regex;
                        $by_id{$category . $id} = {};
                    }
                }
            }

            $log->debugf("Index of '%s' is initialized, found: %d items", $self->path, scalar %by_id);
            return \%by_id;
        },
    );
    return \%result;
}

sub clear_index ($self) {
    $log->debugf('%s: %s', (caller (0))[3], $self->path);
    $self->_cache->expire(__PACKAGE__ . $self->url->to_string);
    return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

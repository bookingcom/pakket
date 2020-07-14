package Pakket::Repository::Backend::S3;

# ABSTRACT: A remote S3-compatible backend repository

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

# core
use Carp;
use Time::HiRes qw(gettimeofday);
use experimental qw(declared_refs refaliasing signatures);

# non core
use Log::Any qw($log);
use Net::Amazon::S3;
use Net::Amazon::S3::Client;
use Net::Amazon::S3::Client::Object;
use Path::Tiny;
use Try::Tiny;

# local
use Pakket::Utils::Package qw(
    parse_package_id
);

has 's3' => (
    'is'      => 'ro',
    'isa'     => 'Net::Amazon::S3::Client',
    'lazy'    => 1,
    'clearer' => 'clear_client',
    'builder' => '_build_s3_client',
);

has 's3_bucket' => (
    'is'      => 'rw',
    'isa'     => 'Net::Amazon::S3::Client::Bucket',
    'lazy'    => 1,
    'clearer' => 'clear_bucket',
    'builder' => '_build_s3_bucket',
);

has [qw(host bucket)] => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
);

has 'index' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'lazy'    => 1,
    'clearer' => 'clear_index',
    'builder' => '_build_index',
);

has 'last_index_update_time' => (
    'is'      => 'ro',
    'isa'     => 'Num',
    'default' => sub {gettimeofday()},
);

has 'file_extension' => (
    'is'      => 'ro',
    'isa'     => 'Str',
    'default' => sub {''},
);

has 'aws_access_key_id' => (
    'is'      => 'ro',
    'isa'     => 'Str',
    'default' => sub {$ENV{'AWS_ACCESS_KEY_ID'}},
);

has 'aws_secret_access_key' => (
    'is'      => 'ro',
    'isa'     => 'Str',
    'default' => sub {$ENV{'AWS_SECRET_ACCESS_KEY'}},
);

with qw(
    Pakket::Role::Repository::Backend
);

use constant {
    'INDEX_UPDATE_INTERVAL' => 60 * 5,
};

sub new_from_uri ($class, $uri) {
    croak($log->criticalf('new_from_uri: not implemented yet'));
}

sub BUILD ($self, @) {
    $self->{'file_extension'} =~ s{^[.]+}{}xms;

    return;
}

sub all_object_ids ($self) {
    $self->_check_index_age();

    return $self->_get_all_object_ids();
}

sub all_object_ids_by_name ($self, $category, $name) {
    $self->_check_index_age();

    my @all_object_ids = try {
        grep {my ($c, $n) = parse_package_id($_); $c eq $category and $n eq $name} keys %{$self->index};
    } catch {
        croak($log->criticalf('Could not get remote all_object_ids, reason: %s', $_));
    };

    return \@all_object_ids;
}

sub has_object ($self, $id) {
    exists $self->index->{$id}
        and return 1;

    my $object = $self->s3_bucket->object('key' => join ('.', $id, $self->file_extension));
    if ($object->exists) {
        $self->index->{$id} = $object;
        return 1;
    }

    return 0;
}

sub remove ($self, $id) {
    $self->_check_index($id);

    try {
        $self->index->{$id}->delete;
    } catch {
        croak($log->criticalf('Could not remove content for %s, reason: %s', $id, $_));
    };

    return 1;
}

sub retrieve_content ($self, $id) {
    $self->_check_index($id);

    my $content = try {
        $self->index->{$id}->get;
    } catch {
        croak($log->criticalf('Could not retrieve content for %s, reason: %s', $id, $_));
    };

    return $content;
}

sub retrieve_location ($self, $id) {
    $self->_check_index($id);

    my $location = try {
        my $tmp_file = Path::Tiny->tempfile('pakket-' . ('X' x 10));
        $self->index->{$id}->get_filename($tmp_file->absolute->stringify);
        $tmp_file;
    } catch {
        croak($log->criticalf('Could not retrieve location for id %s, reason: %s', $id, $_));
    };

    return $location;
}

sub store_content ($self, $id, $content) {
    try {
        my $object = $self->s3_bucket->object(
            'key'       => join ('.', $id, $self->file_extension),
            'acl_short' => 'public-read',
        );
        $object->put($content);
        $self->{'index'}{$id} = $object;
    } catch {
        croak($log->criticalf('Could not store content for id %s, reason: %s', $id, $_));
    };

    return;
}

sub store_location ($self, $id, $file_to_store) {
    try {
        my $object = $self->s3_bucket->object(
            'key'       => join ('.', $id, $self->file_extension),
            'acl_short' => 'public-read',
        );
        $object->put_filename($file_to_store);
        $self->{'index'}{$id} = $object;
    } catch {
        croak($log->criticalf('Could not store location for id %s, reason: %s', $id, $_));
    };

    return;
}

sub _build_s3_client ($self) {
    $log->debugf('Initializing S3 repository backend: %s/%s', $self->host, $self->bucket);
    my $s3 = Net::Amazon::S3->new(
        'host'                  => $self->host,
        'aws_access_key_id'     => $self->aws_access_key_id,
        'aws_secret_access_key' => $self->aws_secret_access_key,
        'retry'                 => 1,
    );

    return Net::Amazon::S3::Client->new('s3' => $s3);
}

sub _build_s3_bucket ($self) {
    return $self->s3->bucket('name' => $self->bucket);
}

sub _build_index ($self) {
    my %index;
    my $stream = $self->s3_bucket->list;
    while (!$stream->is_done) {
        foreach my $object ($stream->items) {
            my ($key) = split (m{[.]$self->{file_extension}$}xms, $object->key);
            $index{$key} = $object;
        }
    }
    $self->{'last_index_update_time'} = gettimeofday();
    $log->debugf("Index of '%s' is initialized, found: %d items", $self->s3_bucket->name, scalar %index);
    return \%index;
}

sub _get_all_object_ids ($self) {
    my @all_object_ids = try {
        keys %{$self->index};
    } catch {
        croak($log->criticalf('Could not get remote all_object_ids, reason: %s', $_));
    };

    return \@all_object_ids;
}

sub _check_index ($self, $id) {
    if (not defined $self->index->{$id}) {
        $log->debugf('Index miss for "%s"', $id);
        $self->_check_index_age();
    }
    return;
}

sub _check_index_age ($self) {

    # clear index if it is older then INDEX_UPDATE_INTERVAL
    if ($self->last_index_update_time < gettimeofday() - INDEX_UPDATE_INTERVAL()) {
        $log->debugf('Clear index for "%s"', $self->s3_bucket->name);
        $self->clear_client();
        $self->clear_bucket();
        $self->clear_index();
    }

    return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

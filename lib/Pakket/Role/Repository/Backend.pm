package Pakket::Role::Repository::Backend;

# ABSTRACT: A role for all repository backends

use v5.22;
use Moose::Role;
use namespace::autoclean;

# core
use experimental qw(declared_refs refaliasing signatures);

# non core
use CHI;
use Log::Any qw($log);

# local
use Pakket::Utils::Package qw(parse_package_id);

# These are helper methods we want the backend to implement
# in order for the Repository to easily use across any backend
requires qw(
    new_from_uri
    all_object_ids all_object_ids_by_name
    has_object remove
    retrieve_content retrieve_location
    store_content store_location
);

has 'file_extension' => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
);

has 'validate_id' => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'default' => 1,
);

has '_cache' => (
    'is'      => 'ro',
    'isa'     => 'CHI::Driver::RawMemory',
    'lazy'    => 1,
    'builder' => '_build_cache',
);

sub check_id ($self, $id) {
    if ($self->validate_id) {
        my ($category, $name, $version, $release) = parse_package_id($id);

        $category && $name && $version && $release
            or croak($log->critical('Invalid id to store: ', $id));
    }
    return 1;
}

sub _build_cache ($self) {
    return CHI->new(
        'driver' => 'RawMemory',
        'global' => 1,
    );
}

1;

__END__

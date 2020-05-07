package Pakket::Role::HasSpecRepo;

# ABSTRACT: Provide spec repo support

use v5.22;
use Moose::Role;
use namespace::autoclean;

# core
use experimental qw(declared_refs refaliasing signatures);

# local
use Pakket::Constants;
use Pakket::Repository::Spec;

has 'spec_repo' => (
    'is'      => 'ro',
    'isa'     => 'Pakket::Repository::Spec',
    'lazy'    => 1,
    'default' => sub ($self) {
        Pakket::Repository::Spec->new(
            'backend'   => $self->spec_repo_backend,
            'log'       => $self->log,
            'log_depth' => $self->log_depth,
        );
    },
);

has 'spec_repo_backend' => (
    'is'      => 'ro',
    'isa'     => 'PakketRepositoryBackend',
    'lazy'    => 1,
    'coerce'  => 1,
    'default' => sub ($self) {$self->config->{'repositories'}{'spec'}},
);

sub add_spec_for_package ($self, $package) {
    if ($self->spec_repo->has_object($package->id) and !$self->overwrite) {
        $self->log->debug('package already exists in spec repo (skipping):', $package->id);
        return;
    }

    $self->log->debug('creating spec for:', $package->id);

    # we had PackageQuery in $package now convert it to Package
    #     my %package_hash = $package->%*;
    #     delete @package_hash{qw(requirement conditions)};
    #     my $final_package = Pakket::Type::Package->new(%package_hash);
    $self->spec_repo->store_package($package);

    return;
}

1;

__END__

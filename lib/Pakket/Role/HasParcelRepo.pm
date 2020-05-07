package Pakket::Role::HasParcelRepo;

# ABSTRACT: Provide parcel repo support

use v5.22;
use Moose::Role;
use namespace::autoclean;

# core
use experimental qw(declared_refs refaliasing signatures);

# local
use Pakket::Repository::Parcel;

has 'parcel_repo' => (
    'is'      => 'ro',
    'isa'     => 'Pakket::Repository::Parcel',
    'lazy'    => 1,
    'clearer' => '_reset_parcel_repo',
    'default' => sub ($self) {
        Pakket::Repository::Parcel->new(
            'backend'   => $self->parcel_repo_backend,
            'log'       => $self->log,
            'log_depth' => $self->log_depth,
        );
    },
);

has 'parcel_repo_backend' => (
    'is'      => 'ro',
    'isa'     => 'PakketRepositoryBackend',
    'lazy'    => 1,
    'coerce'  => 1,
    'clearer' => '_reset_parcel_repo_backend',
    'default' => sub ($self) {$self->config->{'repositories'}{'parcel'}},
);

sub reset_parcel_backend ($self) {
    $self->_reset_parcel_repo_backend();
    $self->_reset_parcel_repo();
    return;
}

1;

__END__

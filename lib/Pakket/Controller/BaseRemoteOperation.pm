package Pakket::Controller::BaseRemoteOperation;

# ABSTRACT: Base class for remote operation controllers

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

# core
use Errno        qw(:POSIX);
use experimental qw(declared_refs refaliasing signatures switch);

# local

has 'repo' => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
);

has 'queries' => (
    'is'       => 'ro',
    'isa'      => 'ArrayRef',
    'required' => 1,
);

with qw(
    Pakket::Role::CanFilterRequirements
    Pakket::Role::HasConfig
    Pakket::Role::HasLog
    Pakket::Role::HasParcelRepo
    Pakket::Role::HasSourceRepo
    Pakket::Role::HasSpecRepo
);

sub get_repo ($self) {
    for ($self->repo) {
        if ($_ eq 'source') {
            return $self->source_repo;
        } elsif ($_ eq 'spec') {
            return $self->spec_repo;
        }
    }
    return $self->parcel_repo;
}

sub check_against_repository ($self, $repo, $requirements) {
    $requirements->%*
        or return;

    $self->log->debugf('checking which objects are available in %s repo...', $repo->type);
    my (\@packages, \@not_found) = $self->filter_packages_in_cache($requirements, $repo->all_objects_cache);
    if (@not_found) {
        foreach my $requirement (@not_found) {
            my @available = $self->available_variants($repo->all_objects_cache->{$requirement->short_name});
            $self->log->warning(
                'Could not find object in',
                $repo->type, 'repo:', $requirement->id, ('( available:', join (', ', @available), ')') x !!@available,
            );
        }

        local $! = ENOENT;
        $self->croak($self->log->critical('Please provide existing object'));
    }
    return \@packages;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

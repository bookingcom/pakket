package Pakket::Controller::List;

# ABSTRACT: List pakket packages

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

# core
use experimental qw(declared_refs refaliasing signatures);

with qw(
    Pakket::Role::HasConfig
    Pakket::Role::HasInfoFile
    Pakket::Role::HasLibDir
    Pakket::Role::HasLog
    Pakket::Role::HasParcelRepo
    Pakket::Role::HasSourceRepo
    Pakket::Role::HasSpecRepo
);

## no critic [InputOutput::RequireBracedFileHandleWithPrint]

sub absent ($self) {
    my %spec_ids = map {$_ => 1} $self->spec_repo->all_object_ids()->@*;
    my %parc_ids = map {$_ => 1} $self->parcel_repo->all_object_ids()->@*;
    delete @spec_ids{keys (%parc_ids)};

    say foreach sort keys %spec_ids;

    return 0;
}

sub installed ($self) {
    say foreach sort $self->load_installed_packages($self->active_dir)->@*;

    return 0;
}

sub parcels ($self) {
    say foreach sort $self->parcel_repo->all_object_ids()->@*;

    return 0;
}

sub sources ($self) {
    say foreach sort $self->source_repo->all_object_ids()->@*;

    return 0;
}

sub specs ($self) {
    say foreach sort $self->spec_repo->all_object_ids()->@*;

    return 0;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

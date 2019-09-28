package Pakket::Repository::Parcel;
# ABSTRACT: A parcel repository

use v5.22;
use Moose;
use MooseX::StrictConstructor;

use Log::Any qw< $log >;
use Path::Tiny;

extends qw< Pakket::Repository >;

sub retrieve_package_parcel {
    my ( $self, $package ) = @_;
    return $self->retrieve_package_file( 'parcel', $package );
}

sub store_package_parcel {
    my ( $self, $package, $parcel_path ) = @_;

    $log->debug("Adding $parcel_path to file");
    my $file = $self->freeze_location($parcel_path);

    $log->debug("Storing $file");
    $self->store_location( $package->id, $file );
}

sub remove_package_parcel {
    my ( $self, $package ) = @_;
    return $self->remove_package_file( 'parcel', $package );
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

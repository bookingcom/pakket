package Pakket::Repository::Source;

# ABSTRACT: A source repository

use v5.22;
use Moose;
use MooseX::StrictConstructor;

use Log::Any qw< $log >;
use Path::Tiny;

extends qw< Pakket::Repository >;

sub retrieve_package_source {
    my ($self, $package) = @_;
    return $self->retrieve_package_file('source', $package);
}

sub store_package_source {
    my ($self, $package, $source_path) = @_;

    $log->debug("Adding $source_path to file");
    my $file = $self->freeze_location($source_path);

    $log->debug("Storing $file");
    $self->store_location($package->id, $file);
}

sub remove_package_source {
    my ($self, $package) = @_;
    return $self->remove_package_file('source', $package);
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

package Pakket::Repository::Parcel;

# ABSTRACT: A parcel repository

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

# core
use experimental qw(declared_refs refaliasing signatures);

extends qw(Pakket::Repository);

sub BUILDARGS ($class, %args) {
    $args{'type'} //= 'parcel';

    return Pakket::Role::HasLog->BUILDARGS(%args); ## no critic [Modules::RequireExplicitInclusion]
}

sub store_package ($self, $package, $path) {
    $self->log->debug('compressing directory:', $path);
    my $file = $self->freeze_location($path);

    $self->log->debug('storing', $self->type, 'to', $package->id);
    $self->store_location($package->id, $file);

    $self->add_to_cache($package->short_name, $package->version, $package->release);

    return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

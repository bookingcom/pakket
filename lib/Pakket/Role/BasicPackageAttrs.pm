package Pakket::Role::BasicPackageAttrs;

# ABSTRACT: Some helpers to print names nicely

use v5.22;
use Moose::Role;
use Pakket::Utils qw< canonical_package_name >;

sub short_name {
    my $self = shift;
    return canonical_package_name($self->category, $self->name);
}

sub full_name {
    my $self = shift;
    return canonical_package_name($self->category, $self->name, $self->version, $self->release);
}

sub id {
    my $self = shift;
    return $self->full_name;
}

no Moose::Role;

1;

__END__

=pod

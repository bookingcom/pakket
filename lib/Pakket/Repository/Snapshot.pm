package Pakket::Repository::Snapshot;

# ABSTRACT: A snapshot repository

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

use Carp;
use experimental qw(declared_refs refaliasing signatures);

extends qw(Pakket::Repository);

sub BUILDARGS ($class, %args) {
    $args{'type'} //= 'snapshot';

    return Pakket::Role::HasLog->BUILDARGS(%args); ## no critic [Modules::RequireExplicitInclusion]
}

__PACKAGE__->meta->make_immutable;

1;

__END__

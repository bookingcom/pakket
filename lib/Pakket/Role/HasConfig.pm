package Pakket::Role::HasConfig;

# ABSTRACT: A role providing access to the Pakket configuration file

use v5.22;
use Moose::Role;
use namespace::autoclean;

# core
use experimental qw(declared_refs refaliasing signatures);

# local
use Pakket::Config;

has 'config' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'lazy'    => 1,
    'builder' => '_build_config',
);

sub _build_config ($self) {
    return Pakket::Config->new()->read_config;
}

1;

__END__

=pod

=head1 DESCRIPTION

This role provides any consumer with a C<config> attribute and builder,
allowing the class to seamlessly load configuration and refer to it, as
well as letting users override it during instantiation.

This role is a wrapper around L<Pakket::Config>.

=head1 ATTRIBUTES

=head2 config

A hashref built from the config file using L<Pakket::Config>.

=cut

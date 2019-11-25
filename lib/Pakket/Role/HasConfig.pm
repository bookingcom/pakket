package Pakket::Role::HasConfig;

# ABSTRACT: A role providing access to the Pakket configuration file

use v5.22;
use Moose::Role;
use Pakket::Config;

has 'config' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'lazy'    => 1,
    'builder' => '_build_config',
);

sub _build_config {
    my $self          = shift;
    my $config_reader = Pakket::Config->new();
    return $config_reader->read_config;
}

no Moose::Role;

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

package Pakket::Requirement;
# ABSTRACT: A Pakket requirement

use Moose;
use MooseX::StrictConstructor;

use Carp     qw< croak >;
use Log::Any qw< $log >;
use Pakket::Utils qw< canonical_package_name >;

has [ qw< category name > ] => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
);

has 'version' => (
    'is'      => 'ro',
    'isa'     => 'Str',
    'default' => sub { '>= 0' },
);

sub short_name {
    my $self = shift;
    return canonical_package_name( $self->category, $self->name );
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

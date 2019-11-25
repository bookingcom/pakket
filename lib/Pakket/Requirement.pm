package Pakket::Requirement;

# ABSTRACT: A Pakket requirement

use v5.22;
use Moose;
use MooseX::StrictConstructor;

use Carp qw< croak >;
use Log::Any qw< $log >;

has [qw< category name >] => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
);

has 'version' => (
    'is'      => 'ro',
    'isa'     => 'Str',
    'default' => sub {'>= 0'},
);

no Moose;
__PACKAGE__->meta->make_immutable;

1;

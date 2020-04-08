package Pakket::Role::Builder;

# ABSTRACT: A role for all builders

use v5.22;
use Moose::Role;

with qw< Pakket::Role::RunCommand >;

requires qw< build_package >;

has 'exclude_packages' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'default' => sub {+{}},
);

has 'test' => (
    'is'      => 'rw',
    'isa'     => 'Int',
    'default' => 0,
);

no Moose::Role;

1;

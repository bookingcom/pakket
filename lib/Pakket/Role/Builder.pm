package Pakket::Role::Builder;

# ABSTRACT: A role for all builders

use Moose::Role;

with qw< Pakket::Role::RunCommand >;

requires qw< build_package >;

no Moose::Role;

1;

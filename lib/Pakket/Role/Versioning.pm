package Pakket::Role::Versioning;
# ABSTRACT: A Versioning role

use v5.22;
use Moose::Role;

requires qw< compare >;

no Moose::Role;

1;

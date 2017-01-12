package Pakket::Role::ConfigReader;
# ABSTRACT: A ConfigReader role

use Moose::Role;

requires qw< read_config >;

no Moose::Role;

1;

package Pakket::Utils::Perl;
# ABSTRACT: Perl specific utilities for Pakket

use strict;
use warnings;
use version 0.77;
use Exporter   qw< import >;
use Path::Tiny qw< path   >;
use Module::CoreList;

our @EXPORT_OK = qw< list_core_modules should_skip_module >;

sub list_core_modules {
    return \%Module::CoreList::upstream;
}

sub should_skip_module {
    my $name = shift;

    if ( Module::CoreList::is_core($name) and !${Module::CoreList::upstream}{$name} ) {
        return 1;
    }

    return 0;
}

1;

#!/usr/bin/env perl

use v5.22;
use strict;
use warnings;
use Test::More 'tests' => 3;
use Pakket::Utils qw< canonical_package_name >;

my $category = 'Foo';
my $package  = 'Bar';
my $version  = 'Baz';
my $revision = 3;

is(
    canonical_package_name( $category, $package, $version, $revision ),
    'Foo/Bar=Baz:3',
    'With category, package, and version',
);

is(
    canonical_package_name( $category, $package, $version ),
    'Foo/Bar=Baz',
    'With category and package, but without version',
);

is(
    canonical_package_name( $category, $package ),
    'Foo/Bar',
    'With category and package, but without version',
);

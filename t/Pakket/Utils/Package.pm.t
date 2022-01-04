#!/usr/bin/env perl

use v5.22;
use strict;
use warnings;

# core
use lib '.';

# non core
use Test2::V0;
use Test2::Tools::Spec;

# local
use Pakket::Utils::Package qw(canonical_name);

use constant {
    'category' => 'Foo_12+35.11',
    'name'     => 'Bar34_13+54-1.8',
    'version'  => 'Baz1.2_3+4-5',
    'release'  => 3,
};
is(
    canonical_name(category(), name(), version(), release()),
    'Foo_12+35.11/Bar34_13+54-1.8=Baz1.2_3+4-5:3',
    'With category, name, version and release',
);

is(
    canonical_name(category(), name(), version()),
    'Foo_12+35.11/Bar34_13+54-1.8=Baz1.2_3+4-5',
    'With category, name and version',
);

is(canonical_name(category(), name()), 'Foo_12+35.11/Bar34_13+54-1.8', 'With category and name, but without version',);

done_testing;

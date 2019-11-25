#!/usr/bin/env perl

use v5.22;
use strict;
use warnings;
use Test::More 'tests' => 1;
use Pakket::Utils qw< encode_json_pretty >;

my $struct = {'x' => ['y', 'z']};
my $string = encode_json_pretty($struct);

## no critic qw(ValuesAndExpressions::ProhibitImplicitNewlines)
is(
    $string,
    '{
   "x" : [
      "y",
      "z"
   ]
}
',
    'Pretty JSON',
);

#!/usr/bin/env perl

use v5.22;
use strict;
use warnings;

use Test::More 'tests' => 2;
use Pakket::Versioning;

my $ver = Pakket::Versioning->new( 'type' => 'Perl' );
isa_ok( $ver, 'Pakket::Versioning' );

my $parsed = $ver->parse_req_string('== 1.4.5, 2.4, < 0.4b');
is_deeply(
    $parsed,
    [
        [ '==', '1.4.5' ],
        [ '>=', '2.4'   ],
        [ '<',  '0.4b'  ],
    ],
    'Correctly parsed the versioning string',
);

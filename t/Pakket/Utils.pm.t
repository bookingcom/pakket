#!/usr/bin/env perl

use v5.22;
use strict;
use warnings;

# core
use lib '.';

# non core
use Test2::V0;
use Test2::Tools::Spec;
use Test2::Plugin::SpecDeclare;

# local
use Pakket::Utils qw(encode_json_pretty normalize_version clean_hash);

my $struct = {
    'x' => ['y', 'z'],
    'a' => 'b',
    'c' => undef,
    'd' => 1,
};
my $string = encode_json_pretty($struct);
my $check  = <<~'END_MESSAGE';
{
   "a" : "b",
   "c" : null,
   "d" : 1,
   "x" : [
      "y",
      "z"
   ]
}
END_MESSAGE

is($string, $check, 'Pretty JSON');

## no critic [ValuesAndExpressions::ProhibitMagicNumbers]
describe 'normalize_version' {
    my @tests = (
        [undef,      '0',        'undef'],
        [0,          '0',        'false number'],
        [42,         '42',       'true number'],
        ['0',        '0',        'false string'],
        ['42',       '42',       'true string'],
        [1.23,       '1.23',     '1.23'],
        ['1.23',     '1.23',     '1.23'],
        ['v1.23',    'v1.23.0',  'v1.23'],
        ['1.23.0',   'v1.23.0',  '1.23'],
        ['v1.23.0',  'v1.23.0',  'v1.23'],
        ['1.2.3',    'v1.2.3',   '1.2.3'],
        ['v1.2.3',   'v1.2.3',   'v1.2.3'],
        [1.200300,   '1.2003',   '1.200300'],
        [1.200301,   '1.200301', '1.200301'],
        ['1.200300', '1.200300', '1.200300'],
        ['1.200301', '1.200301', '1.200301'],
    );

    foreach my $test (@tests) {
        tests 'normalize_version works properly with' {
            is(normalize_version($test->[0]), $test->[1], $test->[2]);
        };
    }

    tests 'normalize_version works properly' {
        like(
            dies {normalize_version('< 42')},
            qr{Invalid\sversion\sformat}xms,
            'Fail on requirement instead of version',
        );
    };
};

describe 'clean_hash' {
    my @tests = (

        # scalars
        [undef, undef, 'undef'],
        [0,     0,     'false number'],
        [42,    42,    'true number'],
        ['0',   '0',   'false string'],
        ['42',  '42',  'true string'],

        # arrays
        [[],      [],      'empty array'],
        [[1, 42], [1, 42], 'non-empty array'],
        [[undef], [undef], 'non-empty undef array'],

        # hashes
        [+{}, {}, 'empty hash'],
        [{'a' => 0},    {'a' => 0},    'one false value number'],
        [{'a' => 42},   {'a' => 42},   'one true value number'],
        [{'a' => '0'},  {'a' => '0'},  'one false value string'],
        [{'a' => '42'}, {'a' => '42'}, 'one false value string'],
        [{'b' => undef}, {}, 'one value undef'],
        [{'c' => {}},    {}, 'one value empty hash'],
        [{'c' => {'d' => undef}}, {}, 'one value undef 2'],
        [{'c' => {'d' => {}}},    {}, 'one value empty hash 2'],
        [{
                'c' => {
                    'd' => undef,
                    'e' => 42,
                    'f' => {'f1' => {}},
                },
                'g' => '42',
            },
            {
                'c' => {'e' => 42},
                'g' => '42',
            },
            'complex hash',
        ],
        [{
                'build'     => {'requires' => {'perl/ExtUtils-MakeMaker' => 0}},
                'configure' => {'requires' => {'perl/ExtUtils-MakeMaker' => 0}},
                'runtime'   => {'requires' => {}},
            },
            {
                'build'     => {'requires' => {'perl/ExtUtils-MakeMaker' => 0}},
                'configure' => {'requires' => {'perl/ExtUtils-MakeMaker' => 0}},
            },
            'hash with prereqs',
        ],
    );

    foreach my $test (@tests) {
        tests 'clean_hash works properly' {
            my $r1 = clean_hash($test->[0]);                                   # scalar context
            is($r1, $test->[1], $test->[2]);
            my ($r2) = +(clean_hash($test->[0]));                              # list context
            is($r2, $test->[1], $test->[2]);
        };
    }
};

done_testing;

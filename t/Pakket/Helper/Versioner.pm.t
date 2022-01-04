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
use Pakket::Helper::Versioner;

my $ver = Pakket::Helper::Versioner->new('type' => 'Perl');

isa_ok($ver, 'Pakket::Helper::Versioner');

my $parsed = $ver->parse_req_string('== 1.4.5, 2.4, < 0.4b');
is($parsed, [['==', '1.4.5'], ['>=', '2.4'], ['<', '0.4b']], 'Correctly parsed the versioning string');

done_testing;

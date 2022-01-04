#!/usr/bin/env perl

use v5.22;
use strict;
use warnings;

# core
use lib '.';

# non core
use Test2::V0;
use Test2::Tools::Basic qw(todo);
use Test2::Tools::Spec;

# local
use t::lib::Utils qw(match_any_item test_prepare_context_corpus test_run);

## no critic [ValuesAndExpressions::ProhibitMagicNumbers]
describe '"list" command integration with fake repo v3' => sub {
    my %ctx = test_prepare_context_corpus('t/corpus/fake.v3');
    my $opt = {
        'env' => {
            'PAKKET_CONFIG_FILE' => $ctx{'app_config'},
        },
    };

    before_all 'prepare test environment'          => sub { };
    before_each 'setup clean environment for test' => sub { };

    tests 'List parcels' => sub {
        my ($ecode, $output) = test_run([$ctx{'app_run'}->@*, 'list', 'par'], $opt, 0);
        match_any_item($output, '^perl/T-A=1.001:1$', 'T-A exact id in the repo');
        match_any_item($output, '^perl/T-A=2.001:1$', 'T-A exact id in the repo');
        match_any_item($output, '^perl/T-B=2.002:2$', 'T-B exact id in the repo');
        match_any_item($output, '^perl/T-C=3.003:3$', 'T-C exact id in the repo');
        match_any_item($output, '^perl/T-D=4.004:1$', 'T-D exact id in the repo');
        match_any_item($output, '^perl/T-D=4.044:1$', 'T-D exact id in the repo');
        is(scalar $output->@*, 6, 'amount in repo');
    };
};

done_testing;

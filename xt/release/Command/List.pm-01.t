#!/usr/bin/env perl

use v5.22;
use warnings;

# core
use lib '.';

# non core
use Test2::V0;
use Test2::Tools::Basic qw(todo);
use Test2::Tools::Spec;

# local
use t::lib::Utils qw(match_any_item test_prepare_context_real test_run);

## no critic [ValuesAndExpressions::ProhibitMagicNumbers]
describe '"list" command integration' => sub {
    my %ctx = test_prepare_context_real();
    my $opt = {
        'env' => {
            'PAKKET_CONFIG_FILE' => $ctx{'app_config'},
        },
    };

    before_all 'prepare test environment' => sub { };
    before_each 'setup clean environment for test' => sub { };

    tests 'List specs' => sub {
        my ($ecode, $output) = test_run([$ctx{'app_run'}->@*, 'list', 'spe'], $opt, 0);
        match_any_item($output, '^perl/version=0.9924:1$', 'exact id in the repo');
        is(scalar $output->@*, 45, 'amount in repo');
    };

    tests 'List sources' => sub {
        my ($ecode, $output) = test_run([$ctx{'app_run'}->@*, 'list', 'sou'], $opt, 0);
        match_any_item($output, 'perl/version=0.9924:1', 'exact id in the repo');
        is(scalar $output->@*, 45, 'amount in repo');
    };

    tests 'List parcels' => sub {
        my ($ecode, $output) = test_run([$ctx{'app_run'}->@*, 'list', 'par'], $opt, 0);
        match_any_item($output, '^perl/version=0.9917:1$', 'exact id in the repo');
        is(scalar $output->@*, 45, 'amount in repo');
    };

    tests 'List installed' => sub {
        my ($ecode, $output) = test_run([$ctx{'app_run'}->@*, 'list', 'inst'], $opt, 0);
        is(scalar $output->@*, 0, 'nothing is installed yet');
    };
};

done_testing;

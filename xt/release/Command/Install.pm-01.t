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
use Test2::Plugin::SpecDeclare;

# local
use t::lib::Utils qw(match_any_item test_prepare_context_real test_run);

## no critic [ValuesAndExpressions::ProhibitMagicNumbers]

describe '"install" command integration' {
    my %ctx = test_prepare_context_real();
    my $opt = {
        'env' => {
            'PAKKET_CONFIG_FILE' => $ctx{'app_config'},
        },
    };

    {
        my $package = 'perl/version';
        my ($ecode, $output) = test_run([$ctx{'app_run'}->@*, 'install', $package], $opt, 0);
        match_any_item($output, 'Finished installing 1 packages');
        ($ecode, $output) = test_run([$ctx{'app_run'}->@*, 'list', 'installed'], $opt, 0);
        match_any_item($output, $package . '=0.9924:1');
        is(scalar $output->@*, 1, 'amount installed');
    }

    {
        my $package = 'perl/CPAN-Meta';
        my ($ecode, $output) = test_run([$ctx{'app_run'}->@*, 'install', $package], $opt, 0);
        match_any_item($output, 'Finished installing 10 packages');
        ($ecode, $output) = test_run([$ctx{'app_run'}->@*, 'list', 'installed'], $opt, 0);
        match_any_item($output, $package);
        is(scalar $output->@*, 11, 'amount installed');
    }

    {
        my $package = 'podlators';
        my ($ecode, $output) = test_run([$ctx{'app_run'}->@*, 'install', $package], $opt, 0);
        match_any_item($output, 'Finished installing 4 packages');
        ($ecode, $output) = test_run([$ctx{'app_run'}->@*, 'list', 'installed'], $opt, 0);
        match_any_item($output, $package);
        is(scalar $output->@*, 15, 'amount installed');
    }

    {
        my $package = 'version';
        my ($ecode, $output) = test_run([$ctx{'app_run'}->@*, 'install', $package], $opt, 0);
        match_any_item($output, 'All packages are already installed');
        ($ecode, $output) = test_run([$ctx{'app_run'}->@*, 'list', 'installed'], $opt, 0);
        match_any_item($output, $package);
        is(scalar $output->@*, 15, 'amount installed');
    }

    {
        my $package = 'version=0.9923:1';
        my ($ecode, $output) = test_run([$ctx{'app_run'}->@*, 'install', '-v', $package], $opt, 0);
        match_any_item($output, 'Going to replace perl/version');
        ($ecode, $output) = test_run([$ctx{'app_run'}->@*, 'list', 'installed'], $opt, 0);
        match_any_item($output, $package);
        is(scalar $output->@*, 15, 'amount installed');
    }

    {
        my $package = 'version=0.9923:1';
        my ($ecode, $output) = test_run([$ctx{'app_run'}->@*, 'install', '-v', $package], $opt, 0);
        match_any_item($output, 'Package is already installed');
        ($ecode, $output) = test_run([$ctx{'app_run'}->@*, 'list', 'installed'], $opt, 0);
        match_any_item($output, $package);
        is(scalar $output->@*, 15, 'amount installed');
    }

    {
        my $package = 'version=0.9923:1';
        my ($ecode, $output) = test_run([$ctx{'app_run'}->@*, 'install', '--overwrite', '-v', $package], $opt, 0);
        match_any_item($output, 'Going to reinstall');
        ($ecode, $output) = test_run([$ctx{'app_run'}->@*, 'list', 'installed'], $opt, 0);
        match_any_item($output, $package);
        is(scalar $output->@*, 15, 'amount installed');
    }
};

done_testing;

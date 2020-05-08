#!/usr/bin/env perl

use v5.22;
use strict;
use warnings;

# core
use lib '.';

# non core
use Path::Tiny;
use Test2::V0;
use Test2::Tools::Basic qw(todo);
use Test2::Tools::Spec;
use Test2::Plugin::SpecDeclare;

# local
use t::lib::Utils qw(match_any_item match_several_items test_prepare_context_real test_run);

describe '"install" accepts STDIN' {
    my %ctx = test_prepare_context_real();
    my $opt = {
        'env' => {
            'PAKKET_CONFIG_FILE' => $ctx{'app_config'},
        },
    };
    my $file = Path::Tiny->tempfile('customXXXXXXXX');
    my $data = <<~ 'END_DATA';
        version
        non-existing
        END_DATA
    $file->spew($data);

    tests 'install from STDIN' => sub {
        {
            my $command
                = 'echo "version" | '
                . join (' ', "PAKKET_CONFIG_FILE=$ctx{'app_config'}", $ctx{'app_run'}->@*)
                . ' install -f - -vvv 2>&1';
            my @output = qx($command);
            match_any_item(\@output, 'matched to: perl/version=0.9924:1');
        }

        {
            my $command
                = 'echo "version" | '
                . join (' ', "PAKKET_CONFIG_FILE=$ctx{'app_config'}", $ctx{'app_run'}->@*)
                . ' install -f - -dvvv 2>&1';
            my @output = qx($command);
            match_any_item(\@output, 'matched to: perl/version=0.9924:1');
        }

        {
            my $command
                = "cat $file | "
                . join (' ', "PAKKET_CONFIG_FILE=$ctx{'app_config'}", $ctx{'app_run'}->@*)
                . ' install -f - -dvvv 2>&1';
            chomp (my @output = qx($command));
            match_several_items(\@output, 'matched to: perl/version=0.9924:1', '^perl/non-existing$');
        }
    };
};

done_testing;

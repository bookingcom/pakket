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

# local
use t::lib::Utils qw(
    match_any_item
    dont_match_any_item
    match_several_items
    test_prepare_context_corpus
    test_run
);
use experimental qw(declared_refs refaliasing signatures);

describe '"install" works properly even if conflict' => sub {
    my %ctx;
    my $opt;

    before_all 'prepare test environment'          => sub { };
    before_each 'setup clean environment for test' => sub {
        %ctx = test_prepare_context_corpus('t/corpus/fake.v3');
        $opt = {
            'env' => {
                'PAKKET_CONFIG_FILE' => $ctx{'app_config'},
            },
        };
    };

    my $file = Path::Tiny->tempfile('customXXXXXXXX');
    my $data = <<~ 'END_DATA';
        version
        non-existing
        END_DATA
    $file->spew($data);

    tests 'Install package T-A and all dependencies' => sub {
        my $command
            = 'echo "T-A=1.001" | '
            . join (' ', "PAKKET_CONFIG_FILE=$ctx{'app_config'}", $ctx{'app_run'}->@*)
            . ' install -f - -vvv 2>&1';
        my @output = qx($command);
        match_any_item(\@output, 'matched to: perl/T-A=1.001:1');
        match_any_item(\@output, 'matched to: perl/T-B=2.002:2');
        match_any_item(\@output, 'matched to: perl/T-C=3.003:3');
        match_any_item(\@output, 'matched to: perl/T-D=4.044:1');
    };

    tests 'Install package T-B and all dependencies' => sub {
        my $package = 'T-B';
        my ($ecode, \@output) = test_run([$ctx{'app_run'}->@*, 'install', $package], $opt, 0);
        match_any_item(\@output, 'Fetching parcel .*: perl/T-B=2.002:2$');
        match_any_item(\@output, 'Fetching parcel .*: perl/T-C=3.003:3 \(as prereq\)$');
        match_any_item(\@output, 'Fetching parcel .*: perl/T-D=4.044:1 \(as prereq\)$');
        match_any_item(\@output, 'Delivering parcel perl/T-B=2.002:2$');
        match_any_item(\@output, 'Delivering parcel perl/T-C=3.003:3$');
        match_any_item(\@output, 'Delivering parcel perl/T-D=4.044:1$');
        match_any_item(\@output, 'Finished installing 3 packages');
        ($ecode, \@output) = test_run([$ctx{'app_run'}->@*, 'list', 'installed'], $opt, 0);
        is(scalar @output, 3, 'amount installed');
    };

    tests 'Install package T-A + conflicted dependency 1' => sub {
        my ($ecode, \@output) = test_run([$ctx{'app_run'}->@*, 'install', 'T-A=1.001', 'T-D=4.004'], $opt, 0);
        match_any_item(\@output, 'Fetching parcel .*: perl/T-A=1.001:1$');
        match_any_item(\@output, 'Fetching parcel .*: perl/T-D=4.004:1$');
        match_any_item(\@output, 'Fetching parcel .*: perl/T-B=2.002:2 \(as prereq\)$');
        match_any_item(\@output, 'Fetching parcel .*: perl/T-C=3.003:3 \(as prereq\)$');
        match_any_item(\@output, 'Dependency conflict detected. Package perl/T-D=4.044:1');
        dont_match_any_item(\@output, 'Package fetched several times, skipping:  perl/T-D=4.004:1');
        dont_match_any_item(\@output, 'Required package is spoiled by some prereq: perl/T-D=4.004');
        dont_match_any_item(\@output, 'You have inconsistency between required and prereq versions');
        match_any_item(\@output, 'Delivering parcel perl/T-A=1.001:1');
        match_any_item(\@output, 'Delivering parcel perl/T-B=2.002:2');
        match_any_item(\@output, 'Delivering parcel perl/T-C=3.003:3');
        match_any_item(\@output, 'Delivering parcel perl/T-D=4.004:1');
        match_any_item(\@output, 'Finished installing 4 packages');
        ($ecode, \@output) = test_run([$ctx{'app_run'}->@*, 'list', 'installed'], $opt, 0);
        is(scalar @output, 4, 'amount installed');
    };

    tests 'Install package T-A + conflicted dependency 2' => sub {
        my ($ecode, \@output) = test_run([$ctx{'app_run'}->@*, 'install', 'T-A=2.001', 'T-D=4.004'], $opt, 0);
        match_any_item(\@output, 'Fetching parcel .*: perl/T-A=2.001:1$');
        match_any_item(\@output, 'Fetching parcel .*: perl/T-D=4.004:1$');
        match_any_item(\@output, 'Fetching parcel .*: perl/T-B=2.002:2 \(as prereq\)$');
        match_any_item(\@output, 'Fetching parcel .*: perl/T-C=3.003:3 \(as prereq\)$');
        match_any_item(\@output, 'Dependency conflict detected. Package perl/T-D=4.044:1');
        dont_match_any_item(\@output, 'Package fetched several times, skipping:  perl/T-D=4.004:1');
        dont_match_any_item(\@output, 'Required package is spoiled by some prereq: perl/T-D=4.004');
        dont_match_any_item(\@output, 'You have inconsistency between required and prereq versions');
        match_any_item(\@output, 'Delivering parcel perl/T-A=2.001:1');
        match_any_item(\@output, 'Delivering parcel perl/T-B=2.002:2');
        match_any_item(\@output, 'Delivering parcel perl/T-C=3.003:3');
        match_any_item(\@output, 'Delivering parcel perl/T-D=4.004:1');
        match_any_item(\@output, 'Finished installing 4 packages');
        ($ecode, \@output) = test_run([$ctx{'app_run'}->@*, 'list', 'installed'], $opt, 0);
        is(scalar @output, 4, 'amount installed');
    };
};

done_testing;

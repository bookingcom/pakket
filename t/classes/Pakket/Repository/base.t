#!/usr/bin/env perl

use v5.22;
use strict;
use warnings;
use Test::More 'tests' => 2;
use Test::Fatal;
use Pakket::Repository;

can_ok(
    Pakket::Repository::,
    qw<
        backend all_object_ids has_object
        store_content retrieve_content remove_content
        store_location retrieve_location remove_location
        retrieve_package_file remove_package_file latest_version_release
    >,
);

like(
    exception { Pakket::Repository->new() },
    qr{You \s did \s not \s specify \s a \s backend }xms,
    'Backend is required to create a Pakket::Repository object',
);

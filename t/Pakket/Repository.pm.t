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
use Pakket::Repository;

can_ok(
    'Pakket::Repository',
    [
        qw(backend all_object_ids has_object store_content retrieve_content
            store_location retrieve_location remove retrieve_package_file remove_package_file),
    ],
    'Has all methods',
);

like(
    dies {Pakket::Repository->new('type' => 'spec')},
    qr{Cannot \screate \sbackend \sof \sgeneric \stype}xms,
    'Backend is required to create a Pakket::Repository object',
);

done_testing;

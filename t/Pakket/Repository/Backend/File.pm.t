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
use Path::Tiny;

# local
use Pakket::Repository::Backend::File;

can_ok(
    'Pakket::Repository::Backend::File',
    [qw(directory file_extension index_file)],
    'Pakket::Repository::Backend::File has all demanded methods',
);

like(
    dies {Pakket::Repository::Backend::File->new()},
    qr{^ Attribute \s [(] directory [)] \s is \s required \s at \s constructor}xms,
    'directory is required to create a new file backend class',
);

my $index_dir = path(qw(t corpus repos.v2 spec));
ok(
    lives {
        Pakket::Repository::Backend::File->new('directory' => $index_dir->stringify);
    },
    'directory attribute can be a string',
);

ok(
    lives {
        Pakket::Repository::Backend::File->new('directory' => $index_dir);
    },
    'directory attribute can be a Path::Tiny object',
);

done_testing;

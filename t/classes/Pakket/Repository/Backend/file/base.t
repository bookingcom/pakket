#!/usr/bin/env perl

use v5.22;
use strict;
use warnings;
use Test::More 'tests' => 4;
use Test::Fatal;
use Path::Tiny qw< path >;
use Pakket::Repository::Backend::file;

can_ok(Pakket::Repository::Backend::file::, qw< directory file_extension index_file >);

my $index_dir = path(qw< t corpus indexes >);

like(
    exception {Pakket::Repository::Backend::file->new()},
    qr{^ Attribute \s \(directory\) \s is \s required \s at \s constructor}xms,
    'directory is required to create a new file backend class',
);

is(
    exception {
        Pakket::Repository::Backend::file->new(
            'directory' => $index_dir->stringify,
        );
    },
    undef,
    'directory attribute can be a string',
);

is(
    exception {
        Pakket::Repository::Backend::file->new('directory' => $index_dir);
    },
    undef,
    'directory attribute can be a Path::Tiny object',
);

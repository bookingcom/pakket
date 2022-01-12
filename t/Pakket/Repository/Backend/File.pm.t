#!/usr/bin/env perl

use v5.22;
use warnings;

# core
use lib '.';

# non core
use Test2::V0;
use Test2::Tools::Spec;
use Path::Tiny;

# local
use Pakket::Repository::Backend::File;

can_ok('Pakket::Repository::Backend::File', [qw(directory file_extension)], 'backend has all demanded attributes');
can_ok(
    'Pakket::Repository::Backend::File',
    [
        qw(all_object_ids all_object_ids_by_name
            has_object remove
            retrieve_content retrieve_location
            store_content store_location
        ),
    ],
    'backend has all demanded methods',
);

my $index_dir      = path(qw(t corpus repos.v3 spec))->absolute;
my $file_extension = 'json';

tests 'new' => sub {
    like(
        dies {Pakket::Repository::Backend::File->new},
        qr{^ Attribute \s [(] directory [)] \s is \s required \s at \s constructor}x,
        'directory is required to create a new backend class',
    );

    like(
        dies {Pakket::Repository::Backend::File->new('directory' => 'blah')},
        qr{^ Attribute \s [(] file_extension [)] \s is \s required \s at \s constructor}x,
        'file_extension is required to create a new backend class',
    );

    like(
        dies {Pakket::Repository::Backend::File->new({'directory' => 'blah'})},
        qr{^ Attribute \s [(] file_extension [)] \s is \s required \s at \s constructor}x,
        'file_extension is required to create a new backend class',
    );

    ok(
        lives {
            Pakket::Repository::Backend::File->new(
                'directory'      => $index_dir->stringify,
                'file_extension' => $file_extension,
            );
        },
        'directory attribute can be a string',
    );

    ok(
        lives {
            Pakket::Repository::Backend::File->new({'directory' => $index_dir->stringify, 'file_extension' => 'json'});
        },
        'directory attribute can be a string',
    );

    ok(
        lives {
            Pakket::Repository::Backend::File->new(
                'directory'      => $index_dir,
                'file_extension' => $file_extension,
            );
        },
        'directory attribute can be a Path::Tiny object',
    );
    my $backend;
    ok(
        lives {
            $backend = Pakket::Repository::Backend::File->new({
                    'directory'      => $index_dir,
                    'file_extension' => $file_extension,
                },
            );
        },
        'directory attribute can be a Path::Tiny object',
    );
    is($backend->directory,      $index_dir->stringify, 'correct directory');
    is($backend->file_extension, '.' . $file_extension, 'correct file_extension');
};

tests 'new_from_uri' => sub {
    my $backend;
    ok(
        lives {
            $backend
                = Pakket::Repository::Backend::File->new_from_uri("file://$index_dir?file_extension=$file_extension");
        },
        'can be built from url',
    );
    is($backend->directory,      $index_dir->stringify, 'correct directory');
    is($backend->file_extension, '.' . $file_extension, 'correct file_extension');
};

done_testing;

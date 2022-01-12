#!/usr/bin/env perl

use v5.22;
use warnings;

# core
use lib '.';

# non core
use Test2::V0;
use Test2::Tools::Spec;
use Mojo::URL;

# local
use Pakket::Repository::Backend::Artifactory;

can_ok(
    'Pakket::Repository::Backend::Artifactory',
    [qw(url path api_key file_extension)],
    'backen has all demanded attributes',
);
can_ok(
    'Pakket::Repository::Backend::Artifactory',
    [
        qw(all_object_ids all_object_ids_by_name
            has_object remove
            retrieve_content retrieve_location
            store_content store_location
        ),
    ],
    'backend has all demanded methods',
);

my $file_extension = 'json';
my $url            = Mojo::URL->new('https://jfrog.domain.com/artifactory');
my $path           = 'pakket/dev/source';
my $full_url       = Mojo::URL->new("artifactory:///$path?file_extension=$file_extension&url=$url");
my $check_url      = $url->clone;
my $check_path     = $path . '/';
$check_url->path->trailing_slash(1);

tests 'new' => sub {
    like(
        dies {Pakket::Repository::Backend::Artifactory->new},
        qr{^ Attribute \s [(] url|file_extension [)] \s is \s required \s at \s constructor}xms,
        'url or file_extension is required to create a new backend class',
    );
    like(
        dies {Pakket::Repository::Backend::Artifactory->new({})},
        qr{^ Attribute \s [(] url|file_extension [)] \s is \s required \s at \s constructor}xms,
        'url or file_extension is required to create a new backend class',
    );

    like(
        dies {Pakket::Repository::Backend::Artifactory->new('url' => $url->to_string)},
        qr{^ Attribute \s [(] file_extension [)] \s is \s required \s at \s constructor}xms,
        'file_extension is required to create a new backend class',
    );

    like(
        dies {Pakket::Repository::Backend::Artifactory->new({'url' => $url->to_string})},
        qr{^ Attribute \s [(] file_extension [)] \s is \s required \s at \s constructor}xms,
        'file_extension is required to create a new backend class',
    );

    like(
        dies {
            Pakket::Repository::Backend::Artifactory->new(
                'url'  => $url->to_string,
                'path' => $path,
            )
        },
        qr{^ Attribute \s [(] file_extension [)] \s is \s required \s at \s constructor}xms,
        'file_extension is required to create a new backend class',
    );

    like(
        dies {
            Pakket::Repository::Backend::Artifactory->new({'url' => $url->to_string, 'path' => $path})
        },
        qr{^ Attribute \s [(] file_extension [)] \s is \s required \s at \s constructor}xms,
        'file_extension is required to create a new backend class',
    );

    ok(
        lives {
            Pakket::Repository::Backend::Artifactory->new(
                'url'            => $url->to_string,
                'file_extension' => $file_extension,
                'path'           => $path,
            );
        },
        'url attribute can be a string',
    );

    ok(
        lives {
            Pakket::Repository::Backend::Artifactory->new({
                    'url'            => $url->to_string,
                    'file_extension' => $file_extension,
                    'path'           => $path,
                },
            );
        },
        'url attribute can be a string',
    );

    ok(
        lives {
            Pakket::Repository::Backend::Artifactory->new(
                'url'            => $url,
                'file_extension' => $file_extension,
                'path'           => $path,
            );
        },
        'url attribute can be a Mojo::URL object',
    );

    my $backend;
    ok(
        lives {
            $backend = Pakket::Repository::Backend::Artifactory->new({
                    'url'            => $url,
                    'file_extension' => $file_extension,
                    'path'           => $path,
                },
            );
        },
        'url attribute can be a Mojo::URL object',
    );
    is($backend->url->to_string, $check_url->to_string, 'correct url');
    is($backend->path,           $check_path,           'correct path');
    is($backend->file_extension, '.' . $file_extension, 'correct file_extension');
};

tests 'new_from_uri' => sub {
    my $backend;
    ok(
        lives {
            $backend = Pakket::Repository::Backend::Artifactory->new_from_uri($full_url);
        },
        'can be built from url',
    );
    is($backend->url->to_string, $check_url->to_string, 'correct url');
    is($backend->path,           $check_path,           'correct path');
    is($backend->file_extension, '.' . $file_extension, 'correct file_extension');
};

done_testing;

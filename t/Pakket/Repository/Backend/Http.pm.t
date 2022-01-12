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
use Pakket::Repository::Backend::Http;

can_ok('Pakket::Repository::Backend::Http', [qw(url file_extension)], 'backend has all demanded methods');
can_ok(
    'Pakket::Repository::Backend::Http',
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
my $url            = Mojo::URL->new('http://localhost/spec');
my $full_url       = $url->clone->query('file_extension' => $file_extension);
my $check_url      = $url->clone;
$check_url->path->trailing_slash(1);

tests 'new' => sub {
    like(
        dies {Pakket::Repository::Backend::Http->new},
        qr{^Invalid params, host is required:},
        'host is required to create a new backend class',
    );
    like(
        dies {Pakket::Repository::Backend::Http->new({})},
        qr{^Invalid params, host is required:},
        'host is required to create a new backend class',
    );

    like(
        dies {Pakket::Repository::Backend::Http->new('url' => $url->to_string)},
        qr{^ Attribute \s [(] file_extension [)] \s is \s required \s at \s constructor}xms,
        'file_extension is required to create a new backend class',
    );

    like(
        dies {Pakket::Repository::Backend::Http->new({'url' => $url})},
        qr{^ Attribute \s [(] file_extension [)] \s is \s required \s at \s constructor}xms,
        'file_extension is required to create a new backend class',
    );

    ok(
        lives {
            Pakket::Repository::Backend::Http->new('url' => $full_url->to_string);
        },
        'url attribute can be a string',
    );

    ok(
        lives {
            Pakket::Repository::Backend::Http->new({'url' => $full_url->to_string});
        },
        'url attribute can be a string',
    );

    ok(
        lives {
            Pakket::Repository::Backend::Http->new('url' => $full_url);
        },
        'url attribute can be a Mojo::URL object',
    );

    my $backend;
    ok(
        lives {
            $backend = Pakket::Repository::Backend::Http->new({'url' => $full_url});
        },
        'url attribute can be a Mojo::URL object',
    );
    is($backend->url->to_string, $check_url->to_string, 'correct url');
    is($backend->file_extension, '.' . $file_extension, 'correct file_extension');
};

tests 'new_from_uri' => sub {
    my $backend;
    ok(
        lives {
            $backend = Pakket::Repository::Backend::Http->new_from_uri($full_url);
        },
        'can be built from url',
    );
    is($backend->url->to_string, $check_url->to_string, 'correct url');
    is($backend->file_extension, '.' . $file_extension, 'correct file_extension');
};

done_testing;

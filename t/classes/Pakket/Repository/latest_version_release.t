#!/usr/bin/env perl

use v5.22;
use strict;
use warnings;
use Test::More 'tests' => 6;
use Pakket::Package;
use Pakket::Repository::Spec;
use lib '.'; use t::lib::Utils;
use Path::Tiny;

# Create directories and set them to be cleaned up when done
# This is used in the config() which requires a string to create
# the repositories
our @DIRS = map Path::Tiny->tempdir, 1 .. 3;
END { unlink for @DIRS }

my $config = t::lib::Utils::config(@DIRS);
my $repo;

subtest 'Setup' => sub {
    isa_ok( $config, 'HASH' );
    my $spec_params;
    ok( $spec_params = $config->{'repositories'}{'spec'},
        'Got spec repo params' );

    isa_ok(
        $repo = Pakket::Repository::Spec->new( 'backend' => $spec_params ),
        'Pakket::Repository::Spec',
    );
};

my @versions = qw<
    1.0
    1.2
    1.2.1
    1.2.2
    1.2.3
    2.0
    2.0.1
    3.1
>;

subtest 'Add packages' => sub {
    foreach my $version (@versions) {
        $repo->store_package_spec(
            Pakket::Package->new(
                'name'     => 'My-Package',
                'category' => 'perl',
                'version'  => $version,
                'release'  => 1,
            ),
        );
    }

    my @all_objects = sort @{ $repo->all_object_ids };
    is_deeply(
        \@all_objects,
        [
            'perl/My-Package=1.0:1',
            'perl/My-Package=1.2:1',
            'perl/My-Package=2.0:1',
            'perl/My-Package=3.1:1',
            'perl/My-Package=v1.2.1:1',
            'perl/My-Package=v1.2.2:1',
            'perl/My-Package=v1.2.3:1',
            'perl/My-Package=v2.0.1:1',
        ],
        'All packages added correctly',
    );
};

subtest 'Find latest version' => sub {
    my ($ver_rel) = $repo->latest_version_release(
        'perl', 'My-Package', '>= 2.0',
    );

    is_deeply( $ver_rel, [ '3.1', '1' ], 'Latest version and release' );
};

subtest 'Find latest versions (with range)' => sub {
    my ($ver_rel) = $repo->latest_version_release(
        'perl', 'My-Package', '>= 2.0, < 3.0',
    );

    is_deeply( $ver_rel, [ 'v2.0.1', '1' ], 'Latest version and release' );
};

subtest 'Find latest versions (with range and NOT)' => sub {
    my ($ver_rel) = $repo->latest_version_release(
        'perl', 'My-Package', '>= 2.0, < 3.0, != 2.0.1',
    );

    is_deeply( $ver_rel, [ '2.0', '1' ], 'Latest version and release' );
};

subtest 'Find latest versions (with different releases)' => sub {
    # Add a few more versions that have different releases
    $repo->remove_package_spec(
        Pakket::Package->new(
            'name'     => 'My-Package',
            'category' => 'perl',
            'version'  => $_,
            'release'  => 1,
        ),
    ) for @versions;

    is_deeply( $repo->all_object_ids, [], 'Cleaned up repo' );

    $repo->store_package_spec(
        Pakket::Package->new(
            'name'     => 'My-Package',
            'category' => 'perl',
            'version'  => $_->[0],
            'release'  => $_->[1],
        ),
    ) for ( [ '1.0', 1 ], [ '2.0', 2 ], [ '2.0', 1 ] );

    is( scalar @{ $repo->all_object_ids }, 3, 'Added three pakages' );

    my ($ver_rel) = $repo->latest_version_release(
        'perl', 'My-Package', '>= 2.0',
    );

    is_deeply( $ver_rel, [ '2.0', '2' ], 'Latest version and release' );
};

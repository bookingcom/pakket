#!/usr/bin/env perl

use v5.22;
use strict;
use warnings;

# core
use lib '.';

# non core
use Log::Any qw($log);

use MooseX::Test::Role;

#use Moose::Meta::Class;
use Path::Tiny;
use Test2::V0;
use Test2::Tools::Spec;
use Test2::Plugin::SpecDeclare;

# local
use Pakket::Helper::Versioner;
use Pakket::Type::Package;
use Pakket::Type::PackageQuery;
use Pakket::Repository::Spec;
use t::lib::Utils;

#requires_ok('Pakket::Role::CanFilterRequirements', qw(filter_packages_in_cache select_package));

my $consumer = consuming_object(
    'Pakket::Role::CanFilterRequirements',
    'methods' => {
        'log' => sub {$log},

        #'method2' => sub {shift->method1()},
    },
);
my %cache = (
    'perl/CPAN-Meta' => {
        '2.150010' => {
            1 => 1,
            3 => 1,
        },
    },
    'perl/CPAN-Meta-YAML' => {
        '0.018' => {
            2 => 1,
            4 => 1,
        },
    },
    'perl/Encode'       => {'3.01' => {1 => 1}},
    'perl/JSON-PP'      => {'4.04' => {2 => 1}},
    'perl/Module-Build' => {
        '0.4229' => {2 => 1},
        'v0.421' => {1 => 1},
    },
    'perl/AnyEvent-YACurl' => {
        '0.13' => {
            1 => 1,
            2 => 1,
        },
        'v0.11.1' => {
            3 => 1,
            4 => 1,
        },
        '0.09_008' => {
            3 => 1,
            4 => 1,
        },
        '0.09_001' => {
            2 => 1,
            5 => 1,
        },
    },
    'perl/version' => {
        '0.9923' => {
            2 => 1,
            5 => 1,
        },
        '0.9924' => {
            1 => 1,
            2 => 1,
        },
    },
    'perl/Tiny' => {
        '0.33' => {map {$_ => 1} 1, 3},
        '0.44' => {map {$_ => 1} 2, 4},
        '0.55' => {map {$_ => 1} 1, 5, 8},
    },
);

#is($consumer->select_package({}, \%cache), 1);
#is($consumer->method2, 1);
#my $consuming_class = consuming_class('Pakket::Role::CanFilterRequirements');
#ok($consuming_class->class_method());
describe 'select_best_version_from_cache' {
    my %tests = (
        'perl/Tiny1'       => [undef, undef],
        'perl/Tiny'        => ['0.55', {map {$_ => 1} 1, 5, 8}],
        'perl/Tiny=0.33'   => ['0.33', {map {$_ => 1} 1, 3}],
        'perl/Tiny===0.33' => ['0.33', {map {$_ => 1} 1, 3}],
        'perl/Tiny=<=0.33' => ['0.33', {map {$_ => 1} 1, 3}],
        'perl/Tiny=>=0.33' => ['0.55', {map {$_ => 1} 1, 5, 8}],
        'perl/Tiny=<0.33'  => [undef, undef],
        'perl/Tiny=>0.33'  => ['0.55', {map {$_ => 1} 1, 5, 8}],
        'perl/Tiny=0.44'   => ['0.44', {map {$_ => 1} 2, 4}],
        'perl/Tiny===0.44' => ['0.44', {map {$_ => 1} 2, 4}],
        'perl/Tiny=<=0.44' => ['0.44', {map {$_ => 1} 2, 4}],
        'perl/Tiny=>=0.44' => ['0.55', {map {$_ => 1} 1, 5, 8}],
        'perl/Tiny=<0.44'  => ['0.33', {map {$_ => 1} 1, 3}],
        'perl/Tiny=>0.44'  => ['0.55', {map {$_ => 1} 1, 5, 8}],
        'perl/Tiny=0.55'   => ['0.55', {map {$_ => 1} 1, 5, 8}],
        'perl/Tiny===0.55' => ['0.55', {map {$_ => 1} 1, 5, 8}],
        'perl/Tiny=<=0.55' => ['0.55', {map {$_ => 1} 1, 5, 8}],
        'perl/Tiny=>=0.55' => ['0.55', {map {$_ => 1} 1, 5, 8}],
        'perl/Tiny=<0.55'  => ['0.44', {map {$_ => 1} 2, 4}],
        'perl/Tiny=>0.55'  => [undef, undef],
        'perl/Tiny=0.66'   => [undef, undef],
        'perl/Tiny===0.66' => [undef, undef],
        'perl/Tiny=<=0.66' => ['0.55', {map {$_ => 1} 1, 5, 8}],
        'perl/Tiny=>=0.66' => [undef, undef],
        'perl/Tiny=<0.66'  => ['0.55', {map {$_ => 1} 1, 5, 8}],
        'perl/Tiny=>0.66'  => [undef, undef],
    );
    tests 'requirement' => sub {
        foreach my $test (sort keys %tests) {
            my $query = Pakket::Type::PackageQuery->new_from_string($test);
            my ($version, $release) = $consumer->select_best_version_from_cache($query, $cache{$query->short_name});
            is($version, $tests{$test}[0], $test . ' version');
            is($release, $tests{$test}[1], $test . ' release');
        }
    };
};

describe 'select_best_package' {
    my %tests = (
        'perl/Tiny1'                       => undef,
        'perl/Tiny'                        => Pakket::Type::Package->new_from_string('perl/Tiny=0.55:8'),
        'perl/Tiny=0.33 '                  => Pakket::Type::Package->new_from_string('perl/Tiny=0.33:3'),
        'perl/Tiny===0.33 '                => Pakket::Type::Package->new_from_string('perl/Tiny=0.33:3'),
        'perl/Tiny=<=0.33 '                => Pakket::Type::Package->new_from_string('perl/Tiny=0.33:3'),
        'perl/Tiny=>=0.33 '                => Pakket::Type::Package->new_from_string('perl/Tiny=0.55:8'),
        'perl/Tiny=<0.33'                  => undef,
        'perl/Tiny= >0.33'                 => Pakket::Type::Package->new_from_string('perl/Tiny=0.55:8'),
        ' perl/Tiny=  0.44'                => Pakket::Type::Package->new_from_string('perl/Tiny=0.44:4'),
        ' perl/Tiny===0.44'                => Pakket::Type::Package->new_from_string('perl/Tiny=0.44:4'),
        ' perl/Tiny=<=0.44'                => Pakket::Type::Package->new_from_string('perl/Tiny=0.44:4'),
        ' perl/Tiny=>=0.44'                => Pakket::Type::Package->new_from_string('perl/Tiny=0.55:8'),
        ' perl/Tiny=< 0.44'                => Pakket::Type::Package->new_from_string('perl/Tiny=0.33:3'),
        ' perl/Tiny=> 0.44'                => Pakket::Type::Package->new_from_string('perl/Tiny=0.55:8'),
        ' perl/Tiny=0.55  '                => Pakket::Type::Package->new_from_string('perl/Tiny=0.55:8'),
        ' perl/Tiny===0.55'                => Pakket::Type::Package->new_from_string('perl/Tiny=0.55:8'),
        ' perl/Tiny=<=0.55'                => Pakket::Type::Package->new_from_string('perl/Tiny=0.55:8'),
        ' perl/Tiny=>=0.55'                => Pakket::Type::Package->new_from_string('perl/Tiny=0.55:8'),
        ' perl/Tiny=<0.55'                 => Pakket::Type::Package->new_from_string('perl/Tiny=0.44:4'),
        'perl/Tiny=>0.55'                  => undef,
        'perl/Tiny=0.55:1'                 => Pakket::Type::Package->new_from_string('perl/Tiny=0.55:1'),
        'perl/Tiny=0.55:3'                 => undef,
        ' perl/Tiny=0.55:5'                => Pakket::Type::Package->new_from_string('perl/Tiny=0.55:5'),
        ' perl/Tiny=0.55:8'                => Pakket::Type::Package->new_from_string('perl/Tiny=0.55:8'),
        'perl/Tiny=<0.55'                  => Pakket::Type::Package->new_from_string('perl/Tiny=0.44:4'),
        'perl/Tiny=<0.55:3'                => undef,
        'perl/Tiny=<0.55:4'                => Pakket::Type::Package->new_from_string('perl/Tiny=0.44:4'),
        'perl/Tiny=<0.55:8'                => undef,
        'perl/Tiny=0.66'                   => undef,
        'perl/Tiny=0.66:8'                 => undef,
        'perl/Tiny===0.66'                 => undef,
        'perl/Tiny=<=0.66'                 => Pakket::Type::Package->new_from_string('perl/Tiny=0.55:8'),
        'perl/Tiny=>=0.66'                 => undef,
        'perl/Tiny=<0.66'                  => Pakket::Type::Package->new_from_string('perl/Tiny=0.55:8'),
        'perl/Tiny=>0.66'                  => undef,
        'perl/version'                     => Pakket::Type::Package->new_from_string('perl/version=0.9924:2'),
        'perl/version=0.9923'              => Pakket::Type::Package->new_from_string('perl/version=0.9923:5'),
        'perl/version=0.9924'              => Pakket::Type::Package->new_from_string('perl/version=0.9924:2'),
        'perl/version=0.9924:1'            => Pakket::Type::Package->new_from_string('perl/version=0.9924:1'),
        'perl/version=0.9924:2'            => Pakket::Type::Package->new_from_string('perl/version=0.9924:2'),
        'perl/version=<0.9924'             => Pakket::Type::Package->new_from_string('perl/version=0.9923:5'),
        'perl/version=>=0'                 => Pakket::Type::Package->new_from_string('perl/version=0.9924:2'),
        'perl/AnyEvent-YACurl'             => Pakket::Type::Package->new_from_string('perl/AnyEvent-YACurl=0.13:2'),
        'perl/AnyEvent-YACurl=>0.10'       => Pakket::Type::Package->new_from_string('perl/AnyEvent-YACurl=0.13:2'),
        'perl/AnyEvent-YACurl=<=0.10'      => Pakket::Type::Package->new_from_string('perl/AnyEvent-YACurl=0.09_008:4'),
        'perl/AnyEvent-YACurl=<0.09_008'   => Pakket::Type::Package->new_from_string('perl/AnyEvent-YACurl=0.09_001:5'),
        'perl/AnyEvent-YACurl=<0.09_008:2' => Pakket::Type::Package->new_from_string('perl/AnyEvent-YACurl=0.09_001:2'),
        'perl/AnyEvent-YACurl===0.10'      => undef,
    );

    tests 'all' => sub {
        foreach my $test (sort keys %tests) {
            my $query = Pakket::Type::PackageQuery->new_from_string($test);
            my $found = $consumer->select_best_package($query, $cache{$query->short_name});
            like($found, $tests{$test}, $test);
        }
    };
};

describe 'filter_packages_in_cache' {
    my %tests = (
        'perl/AnyEvent-YACurl=<0.09_008:2' => Pakket::Type::Package->new_from_string('perl/AnyEvent-YACurl=0.09_001:2'),
        'perl/Tiny'                        => Pakket::Type::Package->new_from_string('perl/Tiny=0.55:8'),
        'perl/Encode'                      => Pakket::Type::Package->new_from_string('perl/Encode=3.01:1'),
        'perl/Test-Simple=2'               => Pakket::Type::PackageQuery->new_from_string('perl/Test-Simple=2'),
        'perl/version=>v1'                 => Pakket::Type::PackageQuery->new_from_string('perl/version=>v1'),
    );
    my %queries = map {
        my $t = Pakket::Type::PackageQuery->new_from_string($_);
        +($t->short_name => $t)
    } keys %tests;

    $_->conditions foreach @tests{qw(perl/Test-Simple=2 perl/version=>v1)},
    values %queries;
    my %queries2 = %queries{qw(perl/Test-Simple perl/version)};

    my ($found, $not_found) = $consumer->filter_packages_in_cache(\%queries, \%cache);
    like(
        [sort {$a->short_name cmp $b->short_name} $found->@*],
        [@tests{qw(perl/AnyEvent-YACurl=<0.09_008:2 perl/Encode perl/Tiny)}],
        'found',
    );

    like(
        [sort {$a->short_name cmp $b->short_name} $not_found->@*],
        [@tests{qw(perl/Test-Simple=2 perl/version=>v1)}],
        'not found',
    );
};

describe 'creating and removing packages in repo' => sub {
    my $dir    = path($ENV{'TMPDIR'});
    my @dirs   = map {my $ret = $dir->child($_); $ret->mkpath; $ret} 1 .. 3;
    my $config = t::lib::Utils::config(@dirs);
    my $repo;
    my @versions = qw(
        1.0
        1.2.2
        1.2
        2.0.1
        3.1
        2.0
        1.2.1
        1.2.3
    );

    before_all 'Setup' {
        ref_ok($config, 'HASH', 'Is a hash');
        my $spec_params = $config->{'repositories'}{'spec'};
        ok($spec_params, 'Got spec repo params');

        isa_ok($repo = Pakket::Repository::Spec->new('backend' => $spec_params), 'Pakket::Repository::Spec');

        foreach my $version (@versions) {
            $repo->store_package(
                Pakket::Type::Package->new(
                    'category' => 'perl',
                    'name'     => 'My-Package',
                    'version'  => $version,
                    'release'  => '1',
                ),
            );
        }
    };

    tests 'Packages were added' => sub {
        my @all_objects = sort $repo->all_object_ids->@*;
        is(
            \@all_objects,
            [
                'perl/My-Package=1.0:1',    'perl/My-Package=1.2:1',
                'perl/My-Package=2.0:1',    'perl/My-Package=3.1:1',
                'perl/My-Package=v1.2.1:1', 'perl/My-Package=v1.2.2:1',
                'perl/My-Package=v1.2.3:1', 'perl/My-Package=v2.0.1:1',
            ],
            'All packages added correctly',
        );
    };

    tests 'Find latest version' {
        my ($ver_rel) = $repo->latest_version_release('perl', 'My-Package', '>= 2.0');

        is($ver_rel, ['3.1', '1'], 'Latest version and release');
    };

    tests 'Find latest versions (with range)' {
        my ($ver_rel) = $repo->latest_version_release('perl', 'My-Package', '>= 2.0, < 3.0');

        is($ver_rel, ['v2.0.1', '1'], 'Latest version and release');
    };

    tests 'Find latest versions (with range and NOT)' {
        my ($ver_rel) = $repo->latest_version_release('perl', 'My-Package', '>= 2.0, < 3.0, != 2.0.1');

        is($ver_rel, ['2.0', '1'], 'Latest version and release');
    };

    after_all 'Find latest versions (with different releases)' {
        $repo->remove_package_file(                                            # Add a few more versions that have different releases
            Pakket::Type::Package->new(
                'category' => 'perl',
                'name'     => 'My-Package',
                'version'  => $_,
                'release'  => '1',
            ),
        ) for @versions;

        is($repo->all_object_ids, [], 'Cleaned up repo');

        $repo->store_package(
            Pakket::Type::Package->new(
                'name'     => 'My-Package',
                'category' => 'perl',
                'version'  => $_->[0],
                'release'  => $_->[1],
            ),
        ) for (['1.0', 1], ['2.0', 2], ['2.0', 1]);

        is(scalar @{$repo->all_object_ids}, 3, 'Added three pakages');

        my ($ver_rel) = $repo->latest_version_release('perl', 'My-Package', '>= 2.0');

        is($ver_rel, ['2.0', '2'], 'Latest version and release');
    };
};

done_testing;

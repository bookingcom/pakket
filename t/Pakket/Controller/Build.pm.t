#!/usr/bin/env perl

use v5.22;
use strict;
use warnings;

# core
use lib '.';

# non core
use Archive::Any;
use Test2::V0;
use Test2::Tools::Spec;
use Path::Tiny;

# local
use Pakket::Controller::Build;
use Pakket::Type::Package;
use t::lib::Utils qw(match_any_item test_prepare_context_real test_run);

my $dir    = $ENV{'TMPDIR'} ? path($ENV{'TMPDIR'}) : Path::Tiny->tempdir;
my @dirs   = map {my $ret = $dir->child($_); $ret->mkpath; $ret} 1 .. 3;
my $config = t::lib::Utils::config(@dirs);

can_ok('Pakket::Controller::Build', [qw(execute snapshot_build_dir)]);

tests 'Defaults' => sub {
    my $builder = _create_builder();
    isa_ok($builder,                       'Pakket::Controller::Build');
    isa_ok($builder->spec_repo,            'Pakket::Repository::Spec');
    isa_ok($builder->source_repo,          'Pakket::Repository::Source');
    isa_ok($builder->source_repo->backend, 'Pakket::Repository::Backend::File');
};

tests 'Build simple module' => sub {
    my $builder       = _create_builder();
    my $fake_dist_dir = t::lib::Utils::generate_modules();

    # Unpack each one
    foreach my $tarball ($fake_dist_dir->children) {
        my $archive = Archive::Any->new($tarball);
        ok($archive->extract($fake_dist_dir), 'Extracted successfully');

        # Import each one
        my ($dir_name) = "$tarball" =~ s{ [.]tar [.]gz $}{}rxms;
        my $source_dir = path($dir_name);
        ok($source_dir->is_dir, 'Got directory');

        my ($dist_name) = $source_dir->basename =~ s{ -0[.]01 $}{}rxms;

        $builder->source_repo->store_package(
            Pakket::Type::Package->new(
                'category' => 'perl',
                'name'     => $dist_name,
                'version'  => '0.01',
                'release'  => 1,
            ),
            $source_dir,
        );
    }
};

describe '"build" controller' => sub {
    my %ctx = test_prepare_context_real();
    my $opt = {
        'env' => {
            'PAKKET_CONFIG_FILE' => $ctx{'app_config'},
        },
    };

    tests 'List specs' => sub {
        ok(1);
    };
};

sub _create_builder {
    return Pakket::Controller::Build->new(
        'config' => $config,
        'phases' => [qw(configure build runtime)],
        'types'  => [qw(requires)],
    );
}

done_testing;

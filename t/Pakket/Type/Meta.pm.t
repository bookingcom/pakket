#!/usr/bin/env perl

use v5.22;
use strict;
use warnings;

# core
use lib '.';

# non core
use JSON::MaybeXS;
use Path::Tiny;
use Test2::V0;
use Test2::Tools::Spec;
use YAML;

# local
use Pakket::Type::Meta;

tests 'default constructors' => sub {
    ok(lives {Pakket::Type::Meta->new()}, 'Can be created with minimal amount of params')
        or diag($@);
};

describe 'metadata' => sub {
    describe 'v3' => sub {
        my $metadata_dir = path(qw(t corpus repos.v3 meta perl));
        my $impl_dir     = path(qw(t corpus metadata perl));
        my @metas        = $metadata_dir->children;
        foreach my $file (@metas) {
            my $meta = Pakket::Type::Meta->new_from_metafile($file)->as_hash;
            my $impl = YAML::Load($impl_dir->child($file->basename)->slurp_utf8)->{'Pakket'};
            delete $impl->{'version'};
            delete $meta->{'version'};
            tests 'check file' => sub {
                is($meta, $impl, $file->basename);
            };
        }
    };
};

describe 'specfile' => sub {
    describe 'v3' => sub {
        my $specs_dir = path(qw(t corpus repos.v3 spec perl));
        my $impl_dir  = path(qw(t corpus metadata perl));
        my @specs     = $specs_dir->children;
        foreach my $file (@specs) {
            my $impl_file = $impl_dir->child($file->basename);

            # $impl_file->exists
            #     or next;

            my $meta = Pakket::Type::Meta->new_from_specdata(decode_json($file->slurp_utf8));
            tests 'check file' => sub {
                ok(
                    lives {$meta = Pakket::Type::Meta->new_from_specdata(decode_json($file->slurp_utf8))},
                    'Can be created from specfile v3: ' . $file->basename,
                ) or diag($@);

                # my $impl = YAML::Load($impl_dir->child($impl_file)->slurp_utf8)->{'Pakket'};
                # is($meta->as_hash, $impl, $file->basename);
            };
        }
    };
};

done_testing;

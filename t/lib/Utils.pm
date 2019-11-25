package t::lib::Utils;

use v5.22;
use strict;
use warnings;
use Module::Faker;
use Path::Tiny qw< path >;
use Pakket::Log;
use Pakket::Repository::Backend::file;
use Log::Any::Adapter;
use Log::Dispatch;

Log::Any::Adapter->set(
    'Dispatch',
    'dispatcher' => arg_default_logger(),
);

sub arg_default_logger {
    return $_[1] || Log::Dispatch->new(
        'outputs' => [[
                'Screen',
                'min_level' => 'notice',
                'newline'   => 1,
            ],
        ],
    );
}

sub generate_modules {
    my $fake_dist_dir = Path::Tiny->tempdir();

    Module::Faker->make_fakes({
            'source' => path(qw< t corpus fake_perl_mods>),
            'dest'   => $fake_dist_dir,
        },
    );

    return $fake_dist_dir;
}

sub config {
    my @dirs = @_;

    return +{
        'repositories' => {
            'spec'   => "file://$dirs[0]",
            'source' => "file://$dirs[1]",
            'parcel' => "file://$dirs[2]",
        },
    };
}

1;

package Pakket::Builder::Native;

# ABSTRACT: Build Native Pakket packages

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

use Carp qw< croak >;
use Log::Any qw< $log >;
use Pakket::Log;
use Path::Tiny qw< path >;
use Pakket::Utils qw< generate_env_vars >;

with qw<Pakket::Role::Builder>;

sub build_package {
    my ($self, $package, $build_dir, $top_pkg_dir, $prefix, $use_prefix, $flags) = @_;

    if (   $build_dir->child('configure')->exists
        || $build_dir->child('config')->exists
        || $build_dir->child('Configure')->exists
        || $build_dir->child('cmake')->exists)
    {
        $log->info("Building native package '$package'");

        my $opts = {
            'env' => {generate_env_vars($build_dir, $top_pkg_dir, $prefix, $use_prefix),},
        };

        my $configurator;
        my @configurator_flags = ('--prefix=' . $prefix->absolute);
        if (-f $build_dir->child('configure')) {
            $configurator = './configure';
        } elsif (-f $build_dir->child('config')) {
            $configurator = './config';
        } elsif (-f $build_dir->child('Configure')) {
            $configurator = './Configure';
        } elsif (-e $build_dir->child('cmake')) {
            $configurator       = 'cmake';
            @configurator_flags = ('-DCMAKE_INSTALL_PREFIX=' . $prefix->absolute, '.');
        } else {
            croak(
                $log->critical(
                          "Don't know how to configure native package '$package'"
                        . " (Cannot find executale '[Cc]onfigure' or 'config')",
                ),
            );
        }

        my @seq = (

            # configure
            [$build_dir, [$configurator, @configurator_flags, @{$flags}], $opts],

            # build
            [$build_dir, ['make'], $opts],

            # test
            $self->test ? ([$build_dir, ['make', 'test'], $opts]) : (),

            # install
            [$build_dir, ['make', 'install', "DESTDIR=$top_pkg_dir"], $opts],
        );

        my $success = $self->run_command_sequence(@seq);

        if (!$success) {
            croak($log->critical("Failed to build native package '$package'"));
        }

        $log->info("Done building native package '$package'");
    } else {
        croak($log->critical("Cannot build native package '$package', no '[Cc]onfigure' or 'config'."));
    }

    return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

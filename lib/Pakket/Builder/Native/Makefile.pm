package Pakket::Builder::Native::Makefile;
# ABSTRACT: Build Native Pakket packages that use Makefile

use Moose;
use MooseX::StrictConstructor;
use Log::Any   qw< $log >;
use Path::Tiny qw< path >;
use Pakket::Log;

with qw<Pakket::Role::Builder>;

sub build_package {
    my ( $self, $package, $build_dir, $prefix, $flags ) = @_;

    $log->info("Building Native library: $package");

    my $opts = {
        'env' => {
            $self->generate_env_vars($build_dir, $prefix),
        },
    };

    my $configurator;
    if ( -f $build_dir->child('configure') ) {
        $configurator = './configure';
    } elsif ( -f $build_dir->child('config') ) {
        $configurator = './config';
    } elsif ( -f $build_dir->child('Configure') ) {
        $configurator = './Configure';
    } else {
        $log->critical( "Don't know how to configure $package"
                . " (Cannot find executale 'configure' or 'config')" );
        exit 1;
    }

    my @seq = (

        # configure
        [
            $build_dir,
            [
                $configurator, '--prefix=' . $prefix->absolute,
                @{$flags},
            ],
            $opts,
        ],

        # build
        [ $build_dir, ['make'], $opts, ],

        # install
        [ $build_dir, [ 'make', 'install' ], $opts, ],
    );

    my $success = $self->run_command_sequence(@seq);

    if ( !$success ) {
        $log->critical("Failed to build $package");
        exit 1;
    }

    $log->info("Done preparing $package");

    return;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

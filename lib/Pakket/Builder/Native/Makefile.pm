package Pakket::Builder::Native::Makefile;
# ABSTRACT: Build Native Pakket packages that use Makefile

use Moose;
use MooseX::StrictConstructor;
use Carp qw< croak >;
use Log::Any   qw< $log >;
use Path::Tiny qw< path >;
use Pakket::Log;
use Pakket::Utils qw< generate_env_vars >;

with qw<Pakket::Role::Builder>;

sub build_package {
    my ( $self, $package, $build_dir, $prefix, $flags ) = @_;

    $log->info("Building native package '$package'");

    my $opts = {
        'env' => {
            generate_env_vars($build_dir, $prefix),
        },
    };

    my $configurator;
    my @configurator_flags = ('--prefix=' . $prefix->absolute);
    if ( -f $build_dir->child('configure') ) {
        $configurator = './configure';
    } elsif ( -f $build_dir->child('config') ) {
        $configurator = './config';
    } elsif ( -f $build_dir->child('Configure') ) {
        $configurator = './Configure';
    } elsif ( -e $build_dir->child('cmake') ) {
        $configurator = 'cmake';
        @configurator_flags = ('-DCMAKE_INSTALL_PREFIX=' . $prefix->absolute, '.') ;
    } else {
        croak( $log->critical( "Don't know how to configure native package '$package'"
                . " (Cannot find executale '[Cc]onfigure' or 'config')" ) );
    }

    my @seq = (

        # configure
        [
            $build_dir,
            [
                $configurator, @configurator_flags,
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
        croak( $log->critical("Failed to build native package '$package'") );
    }

    $log->info("Done building native package '$package'");

    return;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

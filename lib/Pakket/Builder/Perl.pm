package Pakket::Builder::Perl;
# ABSTRACT: Build Perl Pakket packages

use Moose;
use MooseX::StrictConstructor;
use English    qw< -no_match_vars >;
use Log::Any   qw< $log >;
use Pakket::Log;

with qw<Pakket::Role::Builder>;

sub build_package {
    my ( $self, $package, $build_dir, $prefix ) = @_;

    $log->info("Building Perl module: $package");

    my $opts = {
        'env' => {
            $self->generate_env_vars($build_dir, $prefix),
        },
    };

    my $install_base = $prefix->absolute;

    # taken from cpanminus
    my %should_use_mm = map +( "perl/$_" => 1 ),
        qw( version ExtUtils-ParseXS ExtUtils-Install ExtUtils-Manifest );

    my @seq;
    if ( $build_dir->child('Build.PL')->exists
        && !exists $should_use_mm{$package} )
    {
        @seq = (

            # configure
            [
                $build_dir,
                [ 'perl', 'Build.PL', '--install_base', $install_base ],
                $opts,
            ],

            # build
            [ $build_dir, ['./Build'], $opts ],

            # install
            [ $build_dir, [ './Build', 'install' ], $opts ],
        );
    } elsif ( $build_dir->child('Makefile.PL')->exists ) {
        @seq = (

            # configure
            [
                $build_dir,
                [ 'perl', 'Makefile.PL', "INSTALL_BASE=$install_base" ],
                $opts,
            ],

            # build
            [ $build_dir, ['make'], $opts ],

            # install
            [ $build_dir, [ 'make', 'install' ], $opts ],
        );
    } else {
        die "Could not find an installer (Makefile.PL/Build.PL)\n";
    }

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

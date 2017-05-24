package Pakket::Builder::Perl;
# ABSTRACT: Build Perl Pakket packages

use Moose;
use MooseX::StrictConstructor;
use English    qw< -no_match_vars >;
use Log::Any   qw< $log >;
use Pakket::Log;
use Pakket::Utils qw< generate_env_vars >;
use Carp ();

with qw<Pakket::Role::Builder>;

sub build_package {
    my ( $self, $package, $build_dir, $prefix, $flags ) = @_;

    $log->info("Building Perl module: $package");

    my %env  = generate_env_vars( $build_dir, $prefix );
    my $opts = { 'env' => \%env };

    foreach my $env_var ( keys %env ) {
        $log->trace( 'export ' . join '=', $env_var, $env{$env_var} );
    }

    my $install_base = $prefix->absolute;

    # taken from cpanminus
    my %should_use_mm = map +( "perl/$_" => 1 ),
        qw( version ExtUtils-ParseXS ExtUtils-Install ExtUtils-Manifest );

    # If you have a Build.PL file but we can't load Module::Build,
    # it means you didn't declare it as a dependency
    # If you have a Makefile.PL, we can at least use that,
    # otherwise, we'll croak
    my $has_build_pl    = $build_dir->child('Build.PL')->exists;
    my $has_makefile_pl = $build_dir->child('Makefile.PL')->exists;

    my @seq;
    if ( $has_build_pl && !exists $should_use_mm{$package} ) {
        # Do we have Module::Build?
        my $has_module_build =
            $self->run_command($build_dir, ['perl','-MModule::Build','-e1'], $opts)
            || $self->run_command($build_dir,[ 'perl','-MModule::Build::Tiny','-e1'], $opts);

        # If you have Module::Build, we can use it!
        if ($has_module_build) {
            @seq = $self->_build_pl_cmds( $build_dir, $install_base, $flags, $opts );
        } else {
            $log->warn(
                'Defined Build.PL but can\'t load Module::Build. Will try Makefile.PL',
            );
        }
    }

    if ($has_makefile_pl && !@seq) {
        @seq = $self->_makefile_pl_cmds( $build_dir, $install_base, $flags, $opts );
    }

    @seq or Carp::croak('Could not find an installer (Makefile.PL/Build.PL)');

    my $success = $self->run_command_sequence(@seq);

    if ( !$success ) {
        Carp::croak( $log->critical("Failed to build $package") );
    }

    $log->info("Done preparing $package");

    return;
}

sub _build_pl_cmds {
    my ( $self, $build_dir, $install_base, $flags, $opts ) = @_;
    return (

        # configure
        [
            $build_dir,
            [ 'perl', '-f', 'Build.PL', '--install_base', $install_base, @{$flags} ],
            $opts,
        ],

        # build
        [ $build_dir, [ 'perl', '-f', './Build' ], $opts ],

        # install
        [ $build_dir, [ 'perl', '-f', './Build', 'install' ], $opts ],
    );
}

sub _makefile_pl_cmds {
    my ( $self, $build_dir, $install_base, $flags, $opts ) = @_;
    return (

        # configure
        [
            $build_dir,
            [ 'perl', '-f', 'Makefile.PL', "INSTALL_BASE=$install_base", @{$flags} ],
            $opts,
        ],

        # build
        [ $build_dir, ['make'], $opts ],

        # install
        [ $build_dir, [ 'make', 'install' ], $opts ],
    );
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

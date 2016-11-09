package Pakket::Role::Builder;

# ABSTRACT: A role for all builders

use Moose::Role;
use Path::Tiny qw< path >;

with qw< Pakket::Role::RunCommand >;

requires qw< build_package >;

sub generate_env_vars {
    my ( $self, $build_dir, $prefix ) = @_;
    my $lib_path = $self->generate_lib_path($prefix);
    my $bin_path = $self->generate_bin_path($prefix);

    my @perl5lib = (
        '.',
        $build_dir,
        path( $prefix, qw<lib perl5> )->absolute->stringify,
    );

    my %perl_opts = (
        'PERL5LIB'                  => join( ':', @perl5lib ),
        'PERL_LOCAL_LIB_ROOT'       => '',
        'PERL5_CPAN_IS_RUNNING'     => 1,
        'PERL5_CPANM_IS_RUNNING'    => 1,
        'PERL5_CPANPLUS_IS_RUNNING' => 1,
        'PERL_MM_USE_DEFAULT'       => 1,
        'PERL_MB_OPT'               => '',
        'PERL_MM_OPT'               => '',
    );

    return (
        'CPATH'           => $prefix->child('include')->stringify,
        'LD_LIBRARY_PATH' => $lib_path,
        'LIBRARY_PATH'    => $lib_path,
        'PATH'            => $bin_path,
        %perl_opts,
    );
}

sub generate_lib_path {
    my ( $self, $prefix ) = @_;

    my $lib_path = $prefix->child('lib')->absolute->stringify;
    if ( defined( my $env_library_path = $ENV{'LD_LIBRARY_PATH'} ) ) {
        $lib_path .= ":$env_library_path";
    }

    return $lib_path;
}

sub generate_bin_path {
    my ( $self, $prefix ) = @_;

    my $bin_path = $prefix->child('bin')->absolute->stringify;
    if ( defined( my $env_bin_path = $ENV{'PATH'} ) ) {
        $bin_path .= ":$env_bin_path";
    }

    return $bin_path;
}

no Moose::Role;

1;

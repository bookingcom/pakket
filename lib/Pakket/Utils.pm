package Pakket::Utils;

# ABSTRACT: Utilities for Pakket

use v5.22;
use strict;
use warnings;
use version 0.77;

use Exporter qw< import >;
use JSON::MaybeXS;

our @EXPORT_OK = qw<
    is_writeable
    generate_env_vars
    canonical_package_name
    encode_json_canonical
    encode_json_pretty
>;

sub is_writeable {
    my $path = shift; # Path::Tiny objects

    while ( !$path->is_rootdir ) {
        $path->exists and return -w $path;
        $path = $path->parent;
    }

    return -w $path;
}

sub generate_env_vars {
    my ($build_dir, $top_pkg_dir, $prefix, $use_prefix, $opts, $manual_env_vars) = @_;
    my $pkg_dir = $top_pkg_dir->child($prefix);

    my $inc = $opts->{'inc'} || '';
    $manual_env_vars //= {};

    my @perl5lib = (
        $pkg_dir->child(qw<lib perl5>)->absolute->stringify,
        ($prefix->child(qw<lib perl5>)->absolute->stringify)x!! $use_prefix,
        $inc ||(),
        $build_dir,
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

    my $lib_path       = generate_lib_path($pkg_dir, $prefix, $use_prefix);
    return (
        'CPATH'           => generate_cpath($pkg_dir, $prefix, $use_prefix),
        'PKG_CONFIG_PATH' => generate_pkgconfig_path($pkg_dir, $prefix, $use_prefix),
        'LD_LIBRARY_PATH' => $lib_path,
        'LIBRARY_PATH'    => $lib_path,
        'PATH'            => generate_bin_path($pkg_dir, $prefix, $use_prefix),
        %perl_opts,
        %{$manual_env_vars},
    );
}

sub generate_cpath {
    my ($pkg_dir, $prefix, $use_prefix) = @_;

    my @paths;
    my @incpaths = $pkg_dir->child('include');
    if ($use_prefix) {
        push(@incpaths, $prefix->child('include'));
    }
    foreach my $path (@incpaths) {
        if ( $path->exists ) {
            push(@paths, $path->absolute->stringify);
            push @paths,  map { $_->absolute->stringify } grep { $_->is_dir } $path->children();
        }
    }
    return join(':', @paths);
}

sub generate_lib_path {
    my ($pkg_dir, $prefix, $use_prefix) = @_;

    my @paths = ($pkg_dir->child('lib')->absolute->stringify);
    if ($use_prefix) {
        push(@paths, $prefix->child('lib')->absolute->stringify);
    }
    if ( defined( my $env_library_path = $ENV{'LD_LIBRARY_PATH'} ) ) {
        push(@paths, $env_library_path);
    }
    return join(':', @paths);
}

sub generate_bin_path {
    my ($pkg_dir, $prefix, $use_prefix) = @_;

    my @paths = ($pkg_dir->child('bin')->absolute->stringify);
    if ($use_prefix) {
        push(@paths, $prefix->child('bin')->absolute->stringify);
    }
    if ( defined( my $env_bin_path = $ENV{'PATH'} ) ) {
        push(@paths, $env_bin_path);
    }
    return join(':', @paths);
}

sub generate_pkgconfig_path {
    my ($pkg_dir, $prefix, $use_prefix) = @_;

    my @paths = ($pkg_dir->child('lib/pkgconfig')->absolute->stringify);
    if ($use_prefix) {
        push(@paths, $prefix->child('lib/pkgconfig')->absolute->stringify);
    }
    if ( defined( my $env_pkgconfig_path = $ENV{'PKG_CONFIG_PATH'} ) ) {
        push(@paths, $env_pkgconfig_path);
    }
    return join(':', @paths);
}

sub canonical_package_name {
    my ( $category, $package, $version, $release ) = @_;

    if ( $version && $release ) {
        return sprintf '%s/%s=%s:%s', $category, $package, $version, $release;
    }

    if ($version) {
        return sprintf '%s/%s=%s', $category, $package, $version;
    }

    return sprintf '%s/%s', $category, $package;
}

sub encode_json_canonical {
    my $content = shift;
    return JSON::MaybeXS->new->canonical->encode($content);
}

sub encode_json_pretty {
    my $content = shift;
    return JSON::MaybeXS->new->pretty->canonical->encode($content);
}

1;

__END__

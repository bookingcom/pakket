package Pakket::Utils;
# ABSTRACT: Utilities for Pakket

use strict;
use warnings;
use version 0.77;
use Exporter   qw< import >;
use Path::Tiny qw< path   >;
use File::HomeDir;
use JSON::MaybeXS;

our @EXPORT_OK = qw< is_writeable generate_json_conf generate_env_vars >;

sub is_writeable {
    my $path = shift; # Path::Tiny objects

    while ( !$path->is_rootdir ) {
        $path->exists and return -w $path;
        $path = $path->parent;
    }

    return -w $path;
}

sub generate_json_conf {
    my $output_file = shift;
    my $config_dir  = shift;
    my $index = {};

    my $output = path( $output_file );
    $output->exists and $index = decode_json( $output->slurp_utf8 );

    my $category_iter = path( $config_dir )->iterator;
    while ( my $category = $category_iter->() ) {
        $category->is_dir and "$category" ne '.'
            or return;

        my $category_name = $category->basename;
        my $dist_iter     = $category->iterator;
        while ( my $dist = $dist_iter->() ) {
            my @versions = map s{.+/([^/]+)\.toml$}{$1}r,
                           grep $_->basename ne 'versioning.toml',
                           $dist->children(qr/\.toml$/);

            my $latest_version;
            if ( $category_name eq 'perl' ) {
                ($latest_version)
                    = sort { version->parse($b) <=> version->parse($a) }
                        @versions;
            } else {
                ($latest_version) = sort { $b cmp $a } @versions;
            }

            $index->{$category_name}{ $dist->basename } = {
                'latest'   => $latest_version,
                'versions' =>
                    { map +( $_ => $dist->basename . "-$_" ), @versions, },
            };

        }
    }

    $output->spew_utf8( JSON::MaybeXS->new->pretty->canonical->encode($index) );
}

sub generate_env_vars {
    my ( $build_dir, $prefix ) = @_;
    my $lib_path = generate_lib_path($prefix);
    my $bin_path = generate_bin_path($prefix);

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
    my $prefix = shift;

    my $lib_path = $prefix->child('lib')->absolute->stringify;
    if ( defined( my $env_library_path = $ENV{'LD_LIBRARY_PATH'} ) ) {
        $lib_path .= ":$env_library_path";
    }

    return $lib_path;
}

sub generate_bin_path {
    my $prefix = shift;

    my $bin_path = $prefix->child('bin')->absolute->stringify;
    if ( defined( my $env_bin_path = $ENV{'PATH'} ) ) {
        $bin_path .= ":$env_bin_path";
    }

    return $bin_path;
}


1;

__END__

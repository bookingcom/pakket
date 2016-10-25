package Pakket::Utils;
# ABSTRACT: Utilities for Pakket

use strict;
use warnings;
use version 0.77;
use Exporter   qw< import >;
use Path::Tiny qw< path   >;
use File::HomeDir;
use JSON::MaybeXS;

our @EXPORT_OK = qw< is_writeable generate_json_conf >;

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

1;

__END__

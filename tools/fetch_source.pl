#!/usr/bin/env perl
use strict;
use warnings;

use MetaCPAN::Client;
use Getopt::Long;
use Path::Tiny;
use TOML;

Getopt::Long::GetOptions(
    "source-dir=s" => \my $source_dir,
    "config-dir=s" => \my $config_dir,
);
-d $config_dir or die "Invalid config dir";
-d $source_dir or die "Invalid source dir";

my %seen;
my $iter = path($config_dir)->iterator( { recurse => 1 } );
while ( my $next = $iter->() ) {
    if ( not $next->is_file or not $next =~ /\.toml$/ ) {
        next;
    }

    my $module = TOML::from_toml( $next->slurp_utf8 );

    $seen{"$module->{Package}{name}-$module->{Package}{version}"} = undef;

    for my $prereqs ( values( %{ $module->{Prereqs}{perl} } ) ) {
        for my $dist ( keys(%$prereqs) ) {
            if ( $dist eq "perl" or $dist eq "perl_mlb" ) {
                next;
            }
            $seen{"$dist-$prereqs->{$dist}{version}"} = undef;
        }
    }
}

my @to_fetch = sort( keys(%seen) );
my $mcpan    = MetaCPAN::Client->new;

open( my $pipe, "| wget --directory-prefix='$source_dir' --input-file=-" );

for my $release_name (@to_fetch) {
    my ( $dist, $version ) = split( /-([^-]+)$/ms, $release_name );
    if ( $version eq "0" ) {

        # just take the latest
        my $release = $mcpan->release($dist);
        print $pipe $release->download_url, "\n";
        next;
    }

    my $res = $mcpan->release(
        {
            all => [ { name => $release_name } ],
        },
    );
    if ( $res->total == 0 ) {
        warn "Couldn't find $dist on MetaCPAN";
        next;
    }

    while ( my $release = $res->next ) {
        print $pipe $release->download_url, "\n";
    }
}

close($pipe);

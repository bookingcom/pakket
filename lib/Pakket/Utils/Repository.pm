package Pakket::Utils::Repository;

# ABSTRACT: Repository utility functions

use v5.22;
use strict;
use warnings;

# core
use Carp;
use Path::Tiny;

# exports
use namespace::clean;
use Exporter qw(import);
our @EXPORT_OK = qw(
    gen_repo_config
);

my %file_ext = (
    'spec'   => 'json',
    'source' => 'tgz',
    'parcel' => 'tgz',
);

sub gen_repo_config {
    my ($self, $type, $directory) = @_;
    $directory or return;

    if ($directory =~ m{^(https?)://([^/:]+):?([^/]+)?(/.*)?$}) {
        my ($protocol, $host, $port, $base_path) = ($1, $2, $3, $4);
        $port or $port = $protocol eq 'http' ? 80 : 443;

        return [
            'HTTP',
            'scheme'    => $protocol,
            'host'      => $host,
            'port'      => $port,
            'base_path' => $base_path,
        ];
    } else {
        my $path = path($directory);
        $path->exists && $path->is_dir
            or croak("Bad directory for $type repo: $path\n");

        return [
            'File',
            'directory'      => $directory,
            'file_extension' => $file_ext{$type},
        ];

    }

    return;
}

1;

__END__

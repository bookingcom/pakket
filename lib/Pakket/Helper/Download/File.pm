package Pakket::Helper::Download::File;

# ABSTRACT: Downloader for local files

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

# core
use Archive::Tar;
use Carp;
use experimental qw(declared_refs refaliasing signatures);

# non core
use Path::Tiny;

with qw(
    Pakket::Role::CanDownload
);

sub BUILD ($self, @) {
    (undef, $self->{'url'}) = split (m{file://}, $self->url);
    return;
}

sub download_to_file ($self, $log) {
    return path($self->url);
}

sub download_to_dir ($self, $log) {
    my $file = $self->download_to_file($log);
    return $self->decompress($file);
}

__PACKAGE__->meta->make_immutable;

1;

__END__

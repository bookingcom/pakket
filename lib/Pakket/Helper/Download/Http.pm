package Pakket::Helper::Download::Http;

# ABSTRACT: Downloader for HTTP files

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

# core
use Carp;
use experimental qw(declared_refs refaliasing signatures);

# non core
use Path::Tiny;

with qw(
    Pakket::Role::HttpAgent
    Pakket::Role::CanDownload
);

sub download_to_file ($self, $log) {
    my $file = Path::Tiny->tempfile;
    my $res  = $self->http_get($self->url)->result;
    $res->save_to($file);
    return $file;
}

sub download_to_dir ($self, $log) {
    my $file = $self->download_to_file($log);
    return $self->decompress($file);
}

__PACKAGE__->meta->make_immutable;

1;

__END__

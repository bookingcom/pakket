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
use HTTP::Tiny;

with qw(
    Pakket::Role::CanDownload
);

sub download_to_file ($self, $log) {
    my $file = Path::Tiny->tempfile;
    my $http = HTTP::Tiny->new();
    my $result
        = $http->mirror($self->url, $file, {'headers' => {'If-Modified-Since' => 'Thu, 1 Jan 1970 01:00:00 GMT'}});
    if (!$result->{'success'}) {
        $log->critical('Status:', $result->{'status'});
        $log->critical('Reason:', $result->{'reason'});
        croak($log->critical(q{Can't download:}, $self->name));
    }
    return $file;
}

sub download_to_dir ($self, $log) {
    my $file = $self->download_to_file($log);
    return $self->decompress($file);
}

__PACKAGE__->meta->make_immutable;

1;

__END__

package Pakket::Downloader::Http;
# ABSTRACT: Http downloader specialisation

use Moose;
use MooseX::StrictConstructor;
use Path::Tiny          qw< path >;
use Types::Path::Tiny   qw< Path >;
use Carp                qw< croak >;
use Log::Any            qw< $log >;
use namespace::autoclean;

extends qw< Pakket::Downloader >;

sub BUILD {
    my ($self) = @_;
}

sub download_to_file {
    my ($self) = @_;

    my $file = Path::Tiny->tempfile;
    my $http = HTTP::Tiny->new();
    my $result = $http->mirror($self->url, $file, {headers => {'If-Modified-Since' => 'Thu, 1 Jan 1970 01:00:00 GMT'}});
    if (!$result->{success}) {
        Carp::croak( "Can't download sources for ", $self->package_name );
    }
    return $file;
}

sub download_to_dir {
    my ($self) = @_;

    my $file = $self->download_to_file();
    return $self->_unpack($file);
}

__PACKAGE__->meta->make_immutable;

1;

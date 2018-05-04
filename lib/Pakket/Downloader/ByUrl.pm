package Pakket::Downloader::ByUrl;

use Pakket::Downloader::Git;
use Pakket::Downloader::Http;
use Pakket::Downloader::File;
use Carp        qw< croak >;
use Log::Any    qw< $log >;

sub create {
    my ($package_name, $url) = @_;

    $log->debugf("Downloading sources for %s (%s)", $package_name, $url);
    if ($url =~ m/^http/) {
        return Pakket::Downloader::Http->new(package_name => $package_name, url => $url);
    } elsif ($url =~ m/^git/) {
        return Pakket::Downloader::Git->new(package_name => $package_name, url => $url);
    } elsif ($url =~ m/^file/) {
        return Pakket::Downloader::File->new(package_name => $package_name, url => $url);
    } else {
        Carp::croak($log->critical("Invalid sources url ($url)"));
    }
}

1;

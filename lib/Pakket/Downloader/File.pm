package Pakket::Downloader::File;
# ABSTRACT: Local downloader specialisation

use Moose;
use MooseX::StrictConstructor;
use Path::Tiny        qw< path >;
use Types::Path::Tiny qw< Path >;
use Carp              qw< croak >;
use Log::Any          qw< $log >;
use namespace::autoclean;

extends qw< Pakket::Downloader >;

sub BUILD {
    my ($self) = @_;
    (undef, $self->{url}) = split('file://', $self->url);
}

sub download_to_file {
    my ($self) = @_;

    return path($self->url);
}

sub download_to_dir {
    my ($self) = @_;

    my $file = $self->download_to_file();
    return $self->_unpack($file);
}

__PACKAGE__->meta->make_immutable;

1;

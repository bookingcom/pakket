package Pakket::Downloader::Git;
# ABSTRACT: Git downloader specialisation

use Moose;
use MooseX::StrictConstructor;
use Path::Tiny          qw< path >;
use Types::Path::Tiny   qw< Path >;
use Carp                qw< croak >;
use Log::Any            qw< $log >;
use Git::Wrapper;
use namespace::autoclean;

extends qw< Pakket::Downloader >;

has 'commit' => (
    is       => 'ro',
    isa      => 'Str',
);

sub BUILD {
    my ($self) = @_;

    ($self->{url}, $self->{commit}) = split('#', $self->url);
    (undef, $self->{url}) = split('git://', $self->url);
}

sub download_to_file {
    my ($self) = @_;

    $self->download_to_dir($self->tempdir->absolute);
    return $self->_pack($self->tempdir->absolute);
}

sub download_to_dir {
    my ($self) = @_;

    $log->debugf( "Processing git repo %s with commit %s", $self->url, $self->commit // '' );
    my $repo = Git::Wrapper->new($self->tempdir->absolute);
    $repo->clone($self->url, $self->tempdir->absolute);
    $repo->checkout(qw/--force --no-track -B pakket/, $self->commit) if $self->commit;
    system('rm -rf ' . $self->tempdir->absolute . '/.git');

    return $self->tempdir->absolute;
}

__PACKAGE__->meta->make_immutable;

1;

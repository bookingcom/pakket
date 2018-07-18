package Pakket::Downloader::Git;
# ABSTRACT: Git downloader specialisation

use Moose;
use MooseX::StrictConstructor;
use Path::Tiny          qw< path >;
use Types::Path::Tiny   qw< Path >;
use Carp                qw< croak >;
use Log::Any            qw< $log >;
use Git::Wrapper;
use URI::Escape;
use namespace::autoclean;

extends qw< Pakket::Downloader >;

has 'commit' => (
    is       => 'ro',
    isa      => 'Str',
);

sub BUILD {
    my ($self) = @_;

    ($self->{url}, $self->{commit}) = split('#', $self->url);
    $self->{url} =~ s|^git://||;
    $self->{url} =~ s|^git[+-]||;

    # substitute GIT_PASSWORD and GIT_USERNAME variables in URI
    if ($self->{url} =~ m/\$GIT_PASSWORD/) {
        if ($ENV{GIT_PASSWORD}) {
            my $pass = uri_escape($ENV{GIT_PASSWORD});
            $self->{url} =~ s/\$GIT_PASSWORD/$pass/g;
        } else {
            $self->{url} =~ s/:\$GIT_PASSWORD//g;
        }
    }
    if ($self->{url} =~ m/\$GIT_USERNAME/) {
        $ENV{GIT_USERNAME} //= $ENV{USER} //= 'git';
        my $name = uri_escape($ENV{GIT_USERNAME});
        $self->{url} =~ s/\$GIT_USERNAME/$name/g;
    }

    return 0;
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

package Pakket::Downloader::Git;
# ABSTRACT: Git downloader specialisation

use v5.22;
use Moose;
use MooseX::StrictConstructor;

use Carp                qw< croak >;
use File::Copy::Recursive;
use Git::Wrapper;
use Log::Any            qw< $log >;
use Path::Tiny          qw< path >;
use Types::Path::Tiny   qw< Path >;
use URI::Escape;

use namespace::autoclean;

extends qw< Pakket::Downloader >;

has 'commit' => (
    'is'  => 'ro',
    'isa' => 'Str',
);

has 'folder' => (
    'is'  => 'ro',
    'isa' => 'Str',
);

sub BUILD {
    my ($self) = @_;

    ($self->{'url'}, $self->{'folder'}) = split m/;f=/, $self->url;
    ($self->{'url'}, $self->{'commit'}) = split m/#/, $self->url;
    $self->{'url'} =~ s|^git://||;
    $self->{'url'} =~ s|^git[+-]||;

    # substitute GIT_PASSWORD and GIT_USERNAME variables in URI
    if ($self->{'url'} =~ m/\$GIT_PASSWORD/) {
        if ($ENV{'GIT_PASSWORD'}) {
            my $pass = uri_escape($ENV{'GIT_PASSWORD'});
            $self->{'url'} =~ s/\$GIT_PASSWORD/$pass/g;
        } else {
            $self->{'url'} =~ s/:\$GIT_PASSWORD//g;
        }
    }
    if ($self->{'url'} =~ m/\$GIT_USERNAME/) {
        $ENV{'GIT_USERNAME'} //= $ENV{'USER'} //= 'git';
        my $name = uri_escape($ENV{'GIT_USERNAME'});
        $self->{'url'} =~ s/\$GIT_USERNAME/$name/g;
    }

    return 0;
}

sub download_to_file {
    my ($self) = @_;

    $self->download_to_dir($self->tempdir->absolute);
    return $self->compress($self->tempdir->absolute);
}

sub download_to_dir {
    my ($self) = @_;

    $log->debugf( 'Processing git repo %s with commit %s', $self->url, $self->commit // '' );
    my $repo = Git::Wrapper->new($self->tempdir->absolute);
    $repo->clone($self->url, $self->tempdir->absolute);
    $self->commit and $repo->checkout(qw/--force --no-track -B pakket/, $self->commit);

    if ($self->folder) {
        my $local_folder = Path::Tiny->tempdir( 'CLEANUP' => 1 );
        ## no critic (Perl::Critic::Policy::Variables::ProhibitPackageVars)
        $File::Copy::Recursive::CopyLink = 0;
        File::Copy::Recursive::dircopy($self->tempdir->child($self->folder), $local_folder);
        return $local_folder->absolute;
    } else {
        return $self->tempdir->absolute;
    }
}

__PACKAGE__->meta->make_immutable;

1;

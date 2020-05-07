package Pakket::Helper::Download;

# ABSTRACT: Download files supporting different protocols

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

# core
use Carp;
use experimental qw(declared_refs refaliasing signatures switch);

# local
use Pakket::Helper::Download::Git;
use Pakket::Helper::Download::Http;
use Pakket::Helper::Download::File;
use Pakket::Type;

has 'strategy' => (
    'is'       => 'ro',
    'does'     => 'PakketDownloadStrategy',
    'coerce'   => 1,
    'required' => 1,
    'handles'  => [qw(
            download_to_file
            download_to_dir
            ),
    ],
);

with qw(
    Pakket::Role::HasLog
);

sub BUILDARGS ($class, %args) {
    my %result = (                                                             # no tidy
        ('log' => $args{'log'}) x !!$args{'log'},
        ('log_depth' => $args{'log_depth'}) x !!$args{'log_depth'},
    );
    delete %args{qw(log log_depth)};

    given ($args{'url'}) {
        when (m/^http/) {
            $result{'strategy'} = Pakket::Helper::Download::Http->new(%args{qw(name url)});
        }
        when (m/^git/) {
            $result{'strategy'} = Pakket::Helper::Download::Git->new(%args{qw(name url)});
        }
        when (m/^file/) {
            $result{'strategy'} = Pakket::Helper::Download::File->new(%args{qw(name url)});
        }
        default {
            croak('Unsupported url:' . $args{'url'});
        }
    }

    return Pakket::Role::HasLog->BUILDARGS(%result); ## no critic [Modules::RequireExplicitInclusion]
}

sub to_file ($self) {
    $self->log->debug('downloading file from:', $self->strategy->url);
    return $self->download_to_file($self->log);
}

sub to_dir ($self) {
    $self->log->debugf(
        'downloading and extracting %s from %s to %s',
        $self->strategy->name, $self->strategy->url, $self->strategy->tempdir->absolute,
    );
    return $self->download_to_dir($self->log);
}

__PACKAGE__->meta->make_immutable;

1;

__END__

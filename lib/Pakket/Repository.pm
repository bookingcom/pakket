package Pakket::Repository;

# ABSTRACT: An object representing a Pakket repository

use Moose;
use Path::Tiny qw< path >;
use Types::Path::Tiny qw< Path >;
use File::HomeDir;
use Pakket::Log;
use Log::Any qw< $log >;
use namespace::autoclean;

has _possible_paths => (
    is      => 'ro',
    isa     => 'ArrayRef',
    default => sub {
        [
            # global:
            path( Path::Tiny->rootdir,    qw< usr local pakket > ),

            # user:
            path( File::HomeDir->my_home, '.pakket' ),

            # local dir:
            path('.pakket'),
        ];
    },
);

has repo_dir => (
    is      => 'ro',
    isa     => Path,
    coerce  => 1,
    builder => '_build_repo_dir',
    coerce  => 1,
);

sub _build_repo_dir {
    my $self = shift;

    # environment variable takes precedence
    $ENV{'PAKKET_REPO'} && -d $ENV{'PAKKET_REPO'}
        and return path( $ENV{'PAKKET_REPO'} );

    foreach my $path ( @{ $self->_possible_paths } ) {
        $path->is_dir and return $path;
    }

    $log->critical('Cannot find pakket repository');
    exit 1;
}

__PACKAGE__->meta->make_immutable;

no Moose;

1;

__END__


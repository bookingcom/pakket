package Pakket::Downloader;
# ABSTRACT: Download sources supporting different protocols

use Moose;
use MooseX::StrictConstructor;
use Archive::Tar;
use File::chdir;
use Carp              qw< croak >;
use Path::Tiny        qw< path >;
use Types::Path::Tiny qw< Path >;
use Log::Any          qw< $log >;

has 'package_name' => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has 'url' => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has 'tempdir' => (
    is      => 'ro',
    isa     => Path,
    coerce  => 1,
    lazy    => 1,
    default => \&_default_tempdir,
);

sub to_file {
    my ($self) = @_;

    $log->debugf( "Downloaging file from %s", $self->url );
    return $self->download_to_file;
}

sub to_dir {
    my ($self) = @_;

    $log->debugf( "Downloaging and extracting from %s", $self->url );
    return $self->download_to_dir;
}

sub _default_tempdir {
    my ($self) = @_;
    return Path::Tiny->tempdir( 'CLEANUP' => 1 );
}

sub _pack {
    my ($self, $base_path) = @_;

    my @files;
    $base_path->visit(
        sub {
            my $path = shift;
            $path->is_file or return;

            push @files, $path;
        },
        { 'recurse' => 1 },
    );
    @files = map {$_->relative($base_path)->stringify} @files;

    my $arch = Archive::Tar->new();
    {
        local $CWD = $base_path;
        $arch->add_files(@files);
    }

    my $file = Path::Tiny->tempfile();
    $log->debug("Writing archive as $file");
    $arch->write( $file->stringify, COMPRESS_GZIP );

    return $file;
}

sub _unpack {
    my ( $self, $file ) = @_;

    my $archive = Archive::Any->new($file);
    if ( $archive->is_naughty ) {
        Carp::croak( $log->critical("Suspicious ($file)") );
    }

    my $dir = Path::Tiny->tempdir( 'CLEANUP' => 1 );
    $archive->extract($dir);

    # Determine if this is a directory in and of itself
    # or whether it's just a bunch of files
    # (This is what Archive::Any refers to as "impolite")
    # It has to be done manually, because the list of files
    # from an archive might return an empty directory listing
    # or none, which confuses us
    my @files = $dir->children();
    if ( @files == 1 && $files[0]->is_dir ) {
        # Polite
        my @inner = $files[0]->children();
        foreach my $infile (@inner) {
            $infile->move(path($dir, $infile->basename));
        }
        rmdir $files[0];
    }

    # Is impolite, meaning it's just a bunch of files
    # (or a single file, but still)
    return $dir;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

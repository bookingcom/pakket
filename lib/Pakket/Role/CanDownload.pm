package Pakket::Role::CanDownload;

# ABSTRACT: Role provides download files

use v5.22;
use Moose::Role;
use namespace::autoclean;

# core
use Archive::Tar;
use Carp;
use experimental qw(declared_refs refaliasing signatures);

# non core
use Archive::Any;
use File::chdir;
use Path::Tiny;
use Types::Path::Tiny qw(Path);

has 'name' => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
);

has 'url' => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
);

has 'tempdir' => (
    'is'      => 'ro',
    'isa'     => Path,
    'coerce'  => 1,
    'lazy'    => 1,
    'builder' => '_build_tempdir',
);

sub compress ($self, $base_path) {
    my @files;
    $base_path->visit(
        sub {
            my $path = shift;
            $path->is_file or return;

            push @files, $path;
        },
        {'recurse' => 1},
    );
    @files = map {$_->relative($base_path)->stringify} @files;

    my $arch = Archive::Tar->new();
    {
        local $CWD = $base_path; ## no critic [Variables::ProhibitLocalVars]
        $arch->add_files(@files);
    }

    my $file = Path::Tiny->tempfile();
    $self->log->debug('writing archive as:', $file);
    $arch->write($file->stringify, COMPRESS_GZIP);

    return $file;
}

sub decompress ($self, $file) {
    my $archive = Archive::Any->new($file);
    if ($archive->is_naughty) {
        croak($self->log->critical('Suspicious archive:', $file));
    }

    my $dir = $self->tempdir;
    $archive->extract($dir);

    # Determine if this is a directory in and of itself
    # or whether it's just a bunch of files
    # (This is what Archive::Any refers to as "impolite")
    # It has to be done manually, because the list of files
    # from an archive might return an empty directory listing
    # or none, which confuses us
    my @files = $dir->children();
    if (@files == 1 && $files[0]->is_dir) {

        # Polite
        my @inner = $files[0]->children();
        foreach my $infile (@inner) {
            $infile->move(path($dir, $infile->basename));
        }
        rmdir $files[0]
            or $self->log->warn('Unable to remove dir:', $files[0]->stringify);
    }

    # Is impolite, meaning it's just a bunch of files
    # (or a single file, but still)
    return $dir;
}

sub _build_tempdir ($self) {
    return Path::Tiny->tempdir(
        'CLEANUP'  => 1,
        'TEMPLATE' => 'pakket-downloader-' . $self->name . '-XXXXXXXXXX',
    );
}

1;

__END__

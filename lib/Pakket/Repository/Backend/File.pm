package Pakket::Repository::Backend::File;

# ABSTRACT: A file-based backend repository

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

# core
use Carp;
use Digest::SHA qw(sha1_hex);
use experimental qw(declared_refs refaliasing signatures);

# non core
use File::NFSLock;
use JSON::MaybeXS qw(decode_json);
use Log::Any qw($log);
use Path::Tiny;
use Regexp::Common qw(URI);
use Types::Path::Tiny qw(Path AbsPath);

# local
use Pakket::Utils qw(encode_json_canonical encode_json_pretty);
use Pakket::Utils::Package qw(
    parse_package_id
);

has 'directory' => (
    'is'       => 'ro',
    'isa'      => AbsPath,
    'coerce'   => 1,
    'required' => 1,
);

has 'file_extension' => (
    'is'      => 'ro',
    'isa'     => 'Str',
    'default' => sub {'sgm'},
);

has 'index_file' => (
    'is'      => 'ro',
    'isa'     => Path,
    'coerce'  => 1,
    'default' => sub ($self) {
        return $self->directory->child('index.json');
    },
);

has 'lock_file' => (
    'is'      => 'ro',
    'isa'     => Path,
    'coerce'  => 1,
    'default' => sub ($self) {
        return $self->directory->child('index.lock');
    },
);

has 'pretty_json' => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'default' => sub {1},
);

has 'mangle_filename' => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'default' => sub {0},
);

has 'index' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'lazy'    => 1,
    'clearer' => 'clear_index',
    'builder' => '_build_index',
);

with qw(
    Pakket::Role::Repository::Backend
);

sub new_from_uri ($class, $uri) {
    $uri =~ m/$RE{'URI'}{'file'}{'-keep'}/xms
        or croak($log->critical('Is not a proper file URI:', $uri));

    my $path = $3;                                                             # perldoc Regexp::Common::URI::file
    return $class->new('directory' => $path);
}

sub BUILD ($self, @) {
    $self->directory->mkpath;

    $self->{'file_extension'} =~ s{^[.]+}{}xms;
    return;
}

sub all_object_ids ($self) {
    my @all_object_ids = keys $self->index->%*;
    return \@all_object_ids;
}

sub all_object_ids_by_name ($self, $category, $name) {
    my @all_object_ids
        = grep {my ($c, $n) = parse_package_id($_); $c eq $category and $n eq $name} keys $self->index->%*;

    return \@all_object_ids;
}

sub has_object ($self, $id) {
    return exists $self->index->{$id};
}

sub remove ($self, $id) {
    my $location = $self->retrieve_location($id);
    $location
        or return 0;

    my $lock = File::NFSLock->new($self->lock_file->stringify, 2, undef, 1000);
    $location->remove;
    $self->_remove_from_index($id);
    return 1;
}

sub retrieve_content ($self, $id) {
    return $self->retrieve_location($id)->slurp_utf8({'binmode' => ':raw'});
}

sub retrieve_location ($self, $id) {
    my $filename = $self->index->{$id};
    $filename
        and return $self->directory->child($filename);

    $log->debug("File for ID '$id' does not exist in storage");
    return 0;
}

sub store_content ($self, $id, $content) {
    my $file_to_store = Path::Tiny->tempfile;
    $file_to_store->spew({'binmode' => ':raw'}, $content);

    return $self->store_location($id, $file_to_store);
}

sub store_location ($self, $id, $file_to_store) {
    my $filename  = $self->_store_in_index($id);
    my $directory = $self->directory;

    return path($file_to_store)->copy($directory->child($filename));
}

sub _build_index ($self) {
    $self->index_file->is_file
        and return decode_json($self->index_file->slurp_utf8);

    if ($self->mangle_filename) {
        return +{};
    }

    my @categories = $self->directory->children();
    my $match      = join ('.', '', $self->file_extension);
    my %result;
    $self->directory->visit(
        sub ($path, $state) {
            $path->is_dir
                or return;
            my $category = $path->basename;
            foreach my $file ($path->children()) {
                my $rel  = $file->relative($self->directory);
                my $name = $rel->stringify =~ s{$match}{}rxms;
                $result{$name} = $rel->stringify;
            }
        },
        {
            'recurse'         => 0,
            'follow_symlinks' => 0,
        },
    );

    return \%result;
}

sub _store_in_index ($self, $id) {
    my $name;
    if ($self->mangle_filename) {
        $name = sha1_hex($id);
    } else {
        $name = $id =~ s{[^[:alnum:].=:_+]}{-}rgx;
    }
    my $filename = join ('.', $name, $self->file_extension);

    my $lock  = File::NFSLock->new($self->lock_file->stringify, 2, undef, 1000);
    my %index = $self->index->%*;
    $index{$id} = $filename;
    $self->_save_index(\%index);

    return $filename;
}

sub _save_index ($self, $index) {
    my $content
        = $self->pretty_json
        ? encode_json_pretty($index)
        : encode_json_canonical($index);

    $self->index_file->spew_utf8($content);
    $self->{'index'} = $index;
    return;
}

sub _remove_from_index ($self, $id) {
    my %index = $self->index->%*;
    delete $index{$id};

    return $self->_save_index(\%index);
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 SYNOPSIS

    my $backend = Pakket::Repository::Backend::File->new(
        'directory'      => '/var/lib/pakket/specs',
        'file_extension' => 'json',
        'index_file'     => 'index.json',
        'pretty_json'    => 1,
    );

    # Handling locations
    $backend->store_location( $id, $path_to_file );
    my $path_to_file = $backend->retrieve_location($id);
    $backend->remove($id);

    # Handling content
    $backend->store_content( $id, $structure );
    my $structure = $backend->retrieve_content($id);

    # Getting data
    my $ids = $backend->all_object_ids; # [ ... ]
    my $ids = $backend->all_object_ids_by_name('perl', 'Path::Tiny');
    if ( $backend->has_object($id) ) {
        ...
    }

=head1 DESCRIPTION

This is a file-based repository backend, allowing a repository to store
information as files. It could store either content or files
("locations").

Every and content is stored using its ID. The backend maintains an
index file of all files so it could locate them quickly. The index file
is stored in a JSON format.

You can control the file extension and the index filename. See below.

=head1 ATTRIBUTES

When creating a new class, you can provide the following attributes:

=head2 directory

This is the directory that will be used. There is no root so it is
better to provide an absolute path.

This is a required parameter.

=head2 file_extension

The extension of files it stores. This has no effect on the format of
the files, only the file extension. The reason is to be able to differ
between files that contain specs versus files of parcels.

Our preference is C<pkt> for packages, C<spkt> for sources, and C<json>
for specs.

Default: B<< C<sgm> >>.

=head2 index_file

The index file contains a list of all packages IDs and the files that
correlate to it. Files are stored by their hashed ID and the index
contains a mapping from the non-hashed ID to the hashed ID.

Default: B<< F<index.json> >>.

=head2 pretty_json

This is a boolean controlling whether the index file should store
pleasantly-readable JSON.

Default: B<1>.

=head2 mangle_filename

When creating file, use sha1(full_package_name) as name of file.
By default uses full_package_name as filename.

This flag is useful when your system doesn't support long filenames. Or for
some another reason you don't like full_package_name as filename.

Default: B<< C<0> >>.

=head1 METHODS

All examples below use a particular string as the ID, but the ID could
be anything you wish. Pakket uses the package ID for it, which consists
of the category, name, version, and release.

=head2 store_location

    $backend->store_location(
        'perl/Path::Tiny=0.100:1',
        '/tmp/myfile.tar.gz',
    );

This method stores the ID with the hashed value and moves the file
under its new name to the directory.

It will return the file path.

=head2 retrieve_location

    my $path = $backend->retrieve_location('perl/Path::Tiny=0.100:1');

This method locates the file in the directory and provides the full
path to it. It does not copy it elsewhere. If you want to change it,
you will need to do this yourself.

=head2 remove

    $backend->remove('perl/Path::Tiny=0.100:1');

This will remove the file from the directory and the index.

=head2 store_content

    my $path = $backend->store_content(
        'perl/Path::Tiny=0.100:1',
        {
            'Package' => {
                'category' => 'perl',
                'name'     => 'Path::Tiny',
                'version'  => 0.100,
                'release'  => 1,
            },

            'Prereqs' => {...},
        },
    );

This method stores content (normally spec files, but could be used for
anything) in the directory. It will create a file with the appropriate
hash ID and save it in the index by serializing it in JSON. This means
you cannot store objects, only plain structures.

It will return the path of that file. However, this is likely not be
very helpful since you would like to retrieve the content. For this,
use C<retrieve_content> described below.

=head2 retrieve_content

    my $struct = $backend->retrieve_content('perl/Path::Tiny=0.100:1');

This method will find the file, unserialize the file content, and
return the structure it stores.

=head2 index

    my $repo_index_content = $backend->index();

This retrieves the unserialized content of the index. It is a hash
reference that maps IDs to hashed IDs that correlate to file paths.

=head2 all_object_ids

    my $ids = $backend->all_object_ids();

Returns all the IDs of objects it stores in an array reference. This
helps find whether an object is available or not.

=head2 all_object_ids_by_name

    my $ids = $backend->all_object_ids_by_name($category, $name);

This is a more specialized method that receives a name and category for
a package and locates all matching IDs in the index. It then returns
them in an array reference.

You do not normally need to use this method.

=head2 has_object

    my $exists = $backend->has_object('perl/Path::Tiny=0.100:1');

This method receives an ID and returns a boolean if it's available.

This method depends on the index so if you screw up with the index, all
bets are off. The methods above make sure the index is consistent.

=cut

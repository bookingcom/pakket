package Pakket::Repository::Backend::File;

# ABSTRACT: A file-based backend repository

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

# core
use Carp;
use experimental qw(declared_refs refaliasing signatures);

# non core
use Log::Any qw($log);
use Mojo::URL;
use Path::Tiny;
use Types::Path::Tiny qw(AbsPath);

use constant {
    'CACHE_TTL' => 60 * 5,
};

has 'directory' => (
    'is'       => 'ro',
    'isa'      => AbsPath,
    'coerce'   => 1,
    'required' => 1,
);

with qw(
    Pakket::Role::Repository::Backend
);

sub new_from_uri ($class, $uri) {
    my $url = Mojo::URL->new($uri);

    $url->is_abs
        or croak($log->criticalf('invalid URL: %s', $url->to_string));

    my $query  = $url->query;
    my %params = (
        'directory' => $url->host . $url->path,
        ('file_extension' => $query->param('file_extension')) x !!defined $query->param('file_extension'),
    );

    return $class->new(\%params);
}

sub BUILD ($self, @) {
    $self->directory->mkpath;

    $self->{'file_extension'} eq ''                                            # add one dot if necessary
        or $self->{'file_extension'} =~ s{^(?:[.]*)(.*)}{.$1}x;

    return;
}

sub all_object_ids ($self) {
    my \%index = $self->index;
    my @all_object_ids = keys %index;
    return \@all_object_ids;
}

sub all_object_ids_by_name ($self, $category, $name) {
    my \%index = $self->index;
    my @all_object_ids = keys %index;

    my @all_object_ids_by_name
        = grep {my ($c, $n) = parse_package_id($_); (!$category || !$c || $c eq $category) && $n eq $name}
        @all_object_ids;

    return \@all_object_ids_by_name;
}

sub has_object ($self, $id) {
    my \%index = $self->index;
    return exists $index{$id};
}

sub remove ($self, $id) {
    my $rel = $self->index->{$id}
        or return;

    $self->directory->child($rel)->remove;
    my \%index = $self->index;
    delete $index{$id};
    return 1;
}

sub retrieve_content ($self, $id) {
    my $rel = $self->index->{$id}
        or croak($log->criticalf('Not found: %s', $id));

    my $content = $self->directory->child($rel)->slurp_raw;
    return $content;
}

sub retrieve_location ($self, $id) {
    my $rel = $self->index->{$id}
        or croak($log->criticalf('Could not retrieve location of %s', $id));

    my $tmp = Path::Tiny->tempfile('pakket-' . ('X' x 10));
    $self->directory->child($rel)->copy($tmp);

    return $tmp;
}

sub store_content ($self, $id, $content) {
    my $file_to_store = Path::Tiny->tempfile;
    $file_to_store->spew_raw($content);

    return $self->store_location($id, $file_to_store);
}

sub store_location ($self, $id, $file_to_store) {
    $self->check_id($id);

    my $rel = $id . $self->file_extension;
    my $abs = $self->directory->child($rel)->absolute;
    $abs->parent->mkpath;
    $file_to_store->copy($abs);

    my \%index = $self->index;
    $index{$id} = $rel;

    return 1;
}

sub index ($self, $force_update = 0) { ## no critic [Subroutines::ProhibitBuiltinHomonyms]
    $self->clear_index if $force_update;

    my \%result = $self->_cache->compute(
        __PACKAGE__ . $self->directory->stringify,
        CACHE_TTL(),
        sub {
            my $regex = qr{\A (.*) $self->{file_extension}\z}x;

            my %by_id;
            $self->directory->visit(
                sub ($path, $) {
                    $path->is_file && $path =~ $regex
                        or return;

                    my $rel = $path->relative($self->directory);
                    my ($id) = $rel =~ $regex;

                    $by_id{$id} = $rel;
                },
                {
                    'recurse'         => 1,
                    'follow_symlinks' => 0,
                },
            );

            $log->debugf("Index of '%s' is initialized, found: %d items", $self->directory, scalar %by_id);
            return \%by_id;
        },
    );
    return \%result;
}

sub clear_index ($self) {
    $self->_cache->expire(__PACKAGE__ . $self->directory->stringify);
    return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 SYNOPSIS

    my $id      = 'perl/Pakket=0:1';
    my $backend = Pakket::Repository::Backend::File->new(
        'directory'      => '/var/lib/pakket/specs',
        'file_extension' => 'json',
    );

    # Handling locations
    $backend->store_location($id, 'path/to/file');
    my $path_to_file = $backend->retrieve_location($id);
    $backend->remove($id);

    # Handling content
    $backend->store_content($id, 'structured_data');
    my $structure = $backend->retrieve_content($id);

    # Getting data
    # my $ids = $backend->all_object_ids; # [ ... ]
    my $ids = $backend->all_object_ids_by_name('perl', 'Path::Tiny');
    if ($backend->has_object($id)) {
        # ...
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

Our preference is C<tgz> for packages, C<tgz> for sources, and C<json>
for specs.

Default: B<< C<tgz> >>.

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
            }
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

    my $repo_index_content = $backend->index;

This retrieves the unserialized content of the index. It is a hash
reference that maps IDs to hashed IDs that correlate to relative file
paths.

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

package Pakket::Repository::Backend::File;
# ABSTRACT: A file-based backend repository

use Moose;
use MooseX::StrictConstructor;

use Carp              qw< croak >;
use JSON::MaybeXS     qw< decode_json >;
use Path::Tiny        qw< path >;
use Log::Any          qw< $log >;
use Types::Path::Tiny qw< Path AbsPath >;
use Digest::SHA       qw< sha1_hex >;
use Pakket::Utils     qw< encode_json_canonical encode_json_pretty >;
use Pakket::Constants qw< PAKKET_PACKAGE_SPEC >;

with qw<
    Pakket::Role::Repository::Backend
>;

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
    'is'       => 'ro',
    'isa'      => Path,
    'coerce'   => 1,
    'default'  => sub {
        my $self = shift;
        return $self->directory->child('index.json');
    },
);

has 'pretty_json' => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'default' => sub {1},
);

sub BUILD {
    my $self = shift;
    if (!$self->directory->exists) {
        croak( $log->criticalf("Directory %s doesn't exist", $self->directory));
    }
}

sub repo_index {
    my $self = shift;
    my $file = $self->index_file;

    $file->is_file
        or return +{};

    return decode_json( $file->slurp_utf8 );
}

sub all_object_ids {
    my $self           = shift;
    my @all_object_ids = keys %{ $self->repo_index };
    return \@all_object_ids;
}

sub all_object_ids_by_name {
    my ( $self, $name, $category ) = @_;
    my @all_object_ids =
        grep { $_ =~ PAKKET_PACKAGE_SPEC(); $1 eq $category and $2 eq $name }
        keys %{ $self->repo_index };
    return \@all_object_ids;
}

sub has_object {
    my ( $self, $id ) = @_;
    return exists $self->repo_index->{$id};
}

sub _store_in_index {
    my ( $self, $id ) = @_;

    # Decide on a proper filename for $id
    # Meaningless extension
    my $filename = sha1_hex($id) . '.' . $self->file_extension;

    # Store in the index
    my $repo_index = $self->repo_index;
    $repo_index->{$id} = $filename;

    $self->_save_index($repo_index);

    return $filename;
}

sub _save_index {
    my ( $self, $repo_index ) = @_;

    my $content
        = $self->pretty_json
        ? encode_json_pretty($repo_index)
        : encode_json_canonical($repo_index);

    $self->index_file->spew_utf8($content);
}

sub _retrieve_from_index {
    my ( $self, $id ) = @_;
    return $self->repo_index->{$id};
}

sub _remove_from_index {
    my ( $self, $id ) = @_;
    my $repo_index = $self->repo_index;
    delete $repo_index->{$id};
    $self->_save_index($repo_index);
}

sub store_location {
    my ( $self, $id, $file_to_store ) = @_;
    my $filename  = $self->_store_in_index($id);
    my $directory = $self->directory;

    return path($file_to_store)->copy( $directory->child($filename) );
}

sub retrieve_location {
    my ( $self, $id ) = @_;
    my $filename = $self->_retrieve_from_index($id);
    $filename
        and return $self->directory->child($filename);

    $log->debug("File for ID '$id' does not exist in storage");
    return;
}

sub remove_location {
    my ( $self, $id ) = @_;
    my $location = $self->retrieve_location($id);
    $location or return;
    $location->remove;
    $self->_remove_from_index($id);
    return 1;
}

sub store_content {
    my ( $self, $id, $content ) = @_;
    my $file_to_store = Path::Tiny->tempfile;
    $file_to_store->spew( { 'binmode' => ':raw' }, $content );
    return $self->store_location( $id, $file_to_store );
}

sub retrieve_content {
    my ( $self, $id ) = @_;
    return $self->retrieve_location($id)
                ->slurp_utf8( { 'binmode' => ':raw' } );
}

sub remove_content {
    my ( $self, $id ) = @_;
    return $self->remove_location($id);
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

__END__

=pod

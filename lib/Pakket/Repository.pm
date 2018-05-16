package Pakket::Repository;
# ABSTRACT: Build in-memory representation of repo

use Moose;
use MooseX::StrictConstructor;

use Path::Tiny;
use Archive::Tar;
use Archive::Extract;
use File::chdir;
use Carp ();
use Log::Any      qw< $log >;
use Pakket::Types qw< PakketRepositoryBackend >;
use Pakket::Constants qw< PAKKET_PACKAGE_SPEC >;
use Pakket::Versioning;

has 'backend' => (
    'is'      => 'ro',
    'does'    => 'PakketRepositoryBackend',
    'coerce'  => 1,
    'lazy'    => 1,
    'builder' => '_build_backend',
    'handles' => [ qw<
        all_object_ids all_object_ids_by_name has_object
        store_content  retrieve_content  remove_content
        store_location retrieve_location remove_location
    > ],
);

sub _build_backend {
    my $self = shift;
    Carp::croak( $log->critical(
        'You did not specify a backend '
      . '(using parameter or URI string)',
    ) );
}

sub BUILD {
    my $self = shift;
    $self->backend();
}

sub retrieve_package_file {
    my ( $self, $type, $package ) = @_;
    my $file = $self->retrieve_location( $package->id );

    if ( !$file ) {
        Carp::croak( $log->criticalf(
            'We do not have the %s for package %s',
            $type, $package->full_name,
        ) );
    }

    my $dir = Path::Tiny->tempdir( 'CLEANUP' => 1 );

    # Prefer system 'tar' instead of 'in perl' archive extractor,
    # because 'tar' memory consumption is very low,
    # but perl extractor is really  greed for memory
    # and we got the error "Out of memory" on KVMs
    $Archive::Extract::PREFER_BIN = 1;

    my $arch = Archive::Extract->new('archive'=>$file->stringify, 'type'=>'tgz');

    unless ($arch->extract('to' => $dir)) {
        Carp::croak($log->criticalf("[%s] Unable to extract %s to %s", $!, $file, $dir));
    }

    return $dir;
}

sub remove_package_file {
    my ( $self, $type, $package ) = @_;
    my $file = $self->retrieve_location( $package->id );

    if ( !$file ) {
        Carp::croak( $log->criticalf(
            'We do not have the %s for package %s',
            $type, $package->full_name,
        ) );
    }

    $log->debug("Removing $type package");
    $self->remove_location( $package->id );
}

sub latest_version_release {
    my ( $self, $category, $name, $req_string ) = @_;

    # This will also convert '0' to '>= 0'
    # (If we want to disable it, we just can just //= instead)
    $req_string ||= '>= 0';

    # Category -> Versioning type class
    my %types = (
        'perl' => 'Perl',
        'native' => 'Perl',
    );

    my %versions;
    foreach my $object_id ( @{ $self->all_object_ids } ) {
        my ( $my_category, $my_name, $my_version, $my_release ) =
            $object_id =~ PAKKET_PACKAGE_SPEC();

        # Ignore what is not ours
        $category eq $my_category and $name eq $my_name
            or next;

        # Add the version
        push @{ $versions{$my_version} }, $my_release;
    }

    my $versioner = Pakket::Versioning->new(
        'type' => $types{$category},
    );

    my $latest_version = $versioner->latest(
        $category, $name, $req_string, keys %versions,
    ) or Carp::croak(
        $log->criticalf(
            'Could not analyze %s/%s to find latest version', $category,
            $name,
        ),
    );

    # return the latest version and latest release available for this version
    return [
        $latest_version,
        ( sort @{ $versions{$latest_version} } )[-1],
    ];
}

sub freeze_location {
    my ( $self, $orig_path ) = @_;

    my $base_path = $orig_path;
    my @files;

    if ( $orig_path->is_file ) {
        $base_path = $orig_path->basename;
        push @files, $orig_path;
    } elsif ( $orig_path->is_dir ) {
        $orig_path->children
            or Carp::croak(
            $log->critical("Cannot freeze empty directory ($orig_path)") );

        $orig_path->visit(
            sub {
                my $path = shift;
                $path->is_file or return;

                push @files, $path;
            },
            { 'recurse' => 1 },
        );
    } else {
        Carp::croak(
            $log->criticalf( "Unknown location type: %s", $orig_path ) );
    }

    @files = map {$_->relative($base_path)->stringify} @files;

    # Write and compress
    my $arch = Archive::Tar->new();
    {
        local $CWD = $base_path; # chdir, to use relative paths in archive
        $arch->add_files(@files);
    }
    my $file = Path::Tiny->tempfile();
    $log->debug("Writing archive as $file");
    $arch->write( $file->stringify, COMPRESS_GZIP );

    return $file;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

__END__

=pod

=head1 SYNOPSIS

    my $repository = Pakket::Repository::Spec->new(
        'backend' => Pakket::Repository::Backend::file->new(...),
    );

    # or
    my $repository = Pakket::Repository::Spec->new(
        'backend' => 'file:///var/lib/',
    );

    ...

This is an abstract class that represents all repositories. It
implements a few generic methods all repositories use. Other than that,
there is very little usage of instantiate this object.

Below is the documentation for these generic methods, as well as how to
set the backend when instantiating. If you are interested in
documentation about particular repository methods, see:

=over 4

=item * L<Pakket::Repository::Spec>

=item * L<Pakket::Repository::Source>

=item * L<Pakket::Repository::Parcel>

=back

=head1 ATTRIBUTES

=head2 backend

    my $repo = Pakket::Repository::Source->new(
        'backend' => Pakket::Repository::Backend::file->new(
            ...
        ),
    );

    # Or the short form:
    my $repo = Pakket::Repository::Source->new(
        'backed' => 'file://...',
    );

    # Or, if you need additional parameters
    my $repo = Pakket::Repository::Source->new(
        'backed'       => 'file://...',
        'backend_opts' => {
            'file_extension' => 'src',
        },
    );

You can either provide an object or a string URI. You can provide

Holds the repository backend implementation. Can be set with either an
object instance or with a string URI. Additional parameters can be set
with C<backend_opts>.

Existing backends are:

=over 4

=item * L<Pakket::Repository::Backend::file>

File-based backend, useful locally.

=item * L<Pakket::Repository::Backend::http>

HTTP-based backend, useful remotely.

=item * L<Pakket::Repository::Backend::dbi>

Database-based backed, useful remotely.

=back

=head2 backend_opts

A hash reference that holds any additional parameters that could either
be part of the URI specification (like a port) or extended beyond the
URI specification (like a file extension).

See examples in C<backend> above.

=head1 METHODS

=head2 retrieve_package_file

=head2 remove_package_file

=head2 latest_version_release

=head2 freeze_location

=head2 all_object_ids

This method will call C<all_object_ids> on the backend.

=head2 all_object_ids_by_name

This method will call C<all_object_ids_by_name> on the backend.

=head2 has_object

This method will call C<has_object> on the backend.

=head2 store_content

This method will call C<store_content> on the backend.

=head2 retrieve_content

This method will call C<retrieve_content> on the backend.

=head2 remove_content

This method will call C<remove_content> on the backend.

=head2 store_location

This method will call C<store_location> on the backend.

=head2 retrieve_location

This method will call C<retrieve_location> on the backend.

=head2 remove_location

This method will call C<remove_location> on the backend.


package Pakket::Repository;
# ABSTRACT: Build in-memory representation of repo

use Moose;
use MooseX::StrictConstructor;

use Path::Tiny;
use Archive::Any;
use Archive::Tar::Wrapper;
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
      . '(using parameter or builder)',
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
    my $arch = Archive::Any->new( $file->stringify );
    $arch->extract($dir);

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

    my @versions;
    foreach my $object_id ( @{ $self->all_object_ids } ) {
        my ( $my_category, $my_name, $my_version, $my_release ) =
            $object_id =~ PAKKET_PACKAGE_SPEC();

        # Ignore what is not ours
        $category eq $my_category and $name eq $my_name
            or next;

        # Add the version
        push @versions, $my_version;
    }

    my $versioner = Pakket::Versioning->new(
        'type' => $types{$category},
    );

    my $latest_version = $versioner->latest( $category, $name, $req_string, @versions );
    $latest_version
        and return [ $latest_version, 1 ];

    Carp::croak( $log->criticalf(
        'Could not analyze %s/%s to find latest version',
        $category, $name,
    ) );
}

sub freeze_location {
    my ( $self, $orig_path ) = @_;

    my $arch = Archive::Tar::Wrapper->new();

    if ( $orig_path->is_file ) {
        $arch->add( $orig_path->basename, $orig_path->stringify, );
    } elsif ( $orig_path->is_dir ) {
        $orig_path->children
            or Carp::croak(
            $log->critical("Cannot freeze empty directory ($orig_path)") );

        $orig_path->visit(
            sub {
                my ( $path, $stash ) = @_;

                $path->is_file
                    or return;

                $arch->add( $path->relative($orig_path)->stringify,
                    $path->stringify, );
            },
            { 'recurse' => 1 },
        );
    } else {
        Carp::croak(
            $log->criticalf( "Unknown location type: %s", $orig_path ) );
    }

    my $file = Path::Tiny->tempfile();

    # Write and compress
    $log->debug("Writing archive as $file");
    $arch->write( $file->stringify, 1 );

    return $file;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

__END__

=pod

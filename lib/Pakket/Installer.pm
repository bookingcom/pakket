package Pakket::Installer;
# ABSTRACT: Install pakket packages into an installation directory

use Moose;
use MooseX::StrictConstructor;
use Path::Tiny            qw< path  >;
use Types::Path::Tiny     qw< Path  >;
use File::Copy::Recursive qw< dircopy >;
use Time::HiRes           qw< time >;
use Log::Any              qw< $log >;
use JSON::MaybeXS         qw< decode_json >;
use Archive::Any;
use English               qw< -no_match_vars >;

use Pakket::Repository::Parcel;
use Pakket::Requirement;
use Pakket::Package;
use Pakket::InfoFile;
use Pakket::LibDir;
use Pakket::Log;
use Pakket::Types     qw< PakketRepositoryBackend >;
use Pakket::Utils     qw< is_writeable >;
use Pakket::Constants qw<
    PARCEL_METADATA_FILE
    PARCEL_FILES_DIR
>;

with qw<
    Pakket::Role::HasConfig
    Pakket::Role::HasParcelRepo
    Pakket::Role::RunCommand
>;

has 'pakket_dir' => (
    'is'       => 'ro',
    'isa'      => Path,
    'coerce'   => 1,
    'required' => 1,
);

sub install {
    my ( $self, @packages ) = @_;

    if ( !@packages ) {
        $log->notice('Did not receive any parcels to deliver');
        return;
    }

    my $work_dir = Pakket::LibDir::create_new_work_dir($self->pakket_dir);

    my $installer_cache = {};
    foreach my $package (@packages) {
        $self->install_package( $package, $work_dir, { 'cache' => $installer_cache } );
    }

    Pakket::LibDir::activate_work_dir($work_dir);

    $log->infof(
        "Finished installing %d packages into $self->pakket_dir",
        scalar keys %{$installer_cache},
    );

    log_success( 'Finished installing: ' . join ', ',
        map $_->full_name, @packages );

    Pakket::LibDir::remove_old_libraries($self->pakket_dir);

    return;
}

sub try_to_install_package {
    my ( $self, $package, $dir, $opts ) = @_;

    $log->debugf( 'Trying to install %s', $package->full_name );

    # First we check whether a package exists, because if not
    # we wil throw a silly critical warning about it
    # This can also speed stuff up, but maybe should be put into
    # "has_package" wrapper function... -- SX
    $self->parcel_repo->has_object( $package->id )
        or return;

    eval {
        $self->install_package( $package, $dir, $opts );
        1;
    } or do {
        $log->debugf( 'Could not install %s', $package->full_name );
        return;
    };

    return 1;
}

sub install_package {
    my ( $self, $package, $dir, $opts ) = @_;
    my $installer_cache = $opts->{'cache'};

    # Are we in a regular (non-bootstrap) mode?
    # Are we using a bootstrap version of a package?
    if ( ! $opts->{'skip_prereqs'} && $package->is_bootstrap ) {
        die $log->critical(
            'You are trying to install a bootstrap version of %s.'
          . ' Please rebuild this package from scratch.',
            $package->full_name,
        );
    }

    # Extracted to use more easily in the install cache below
    my $pkg_cat  = $package->category;
    my $pkg_name = $package->name;

    $log->debugf( "About to install %s (into $dir)", $package->full_name );

    if ( defined $installer_cache->{$pkg_cat}{$pkg_name} ) {
        my $ver_rel = $installer_cache->{$pkg_cat}{$pkg_name};
        my ( $version, $release ) = @{$ver_rel};

        # Check version
        if ( $version ne $package->version ) {
            die $log->criticalf(
                "%s=$version already installed. "
              . "Cannot install new version: %s",
              $package->short_name,
              $package->version,
            );
        }

        # Check release
        if ( $release ne $package->release ) {
            die $log->criticalf(
                '%s=%s:%s already installed. '
              . 'Cannot install new version: %s:%s',
                $package->short_name,
                $version, $release,
                $package->release,
            );
        }

        $log->debugf( '%s already installed.', $package->full_name );

        return;
    } else {
        $installer_cache->{$pkg_cat}{$pkg_name} = [
            $package->version, $package->release,
        ];
    }

    if ( !is_writeable($dir) ) {
        die $log->critical(
            "Can't write to your installation directory ($dir)",
        );
    }

    my $parcel_dir
        = $self->parcel_repo->retrieve_package_parcel($package);

    my $full_parcel_dir = $parcel_dir->child( PARCEL_FILES_DIR() );

    # Get the spec and create a new Package object
    # This one will have the dependencies as well
    my $spec_file    = $full_parcel_dir->child( PARCEL_METADATA_FILE() );
    my $spec         = decode_json $spec_file->slurp_utf8;
    my $full_package = Pakket::Package->new_from_spec($spec);

    my $prereqs = $full_package->prereqs;
    foreach my $prereq_category ( keys %{$prereqs} ) {
        my $runtime_prereqs = $prereqs->{$prereq_category}{'runtime'};

        foreach my $prereq_name ( keys %{$runtime_prereqs} ) {
            my $prereq_data = $runtime_prereqs->{$prereq_name};

            # FIXME: This should be removed when we introduce version ranges
            # This forces us to install the latest version we have of
            # something, instead of finding the latest, based on the
            # version range, which "$prereq_version" contains. -- SX
            my $ver_rel = $self->parcel_repo->latest_version_release(
                $prereq_category,
                $prereq_name,
                $prereq_data->{'version'},
            );

            my ( $prereq_version, $prereq_release ) = @{$ver_rel};

            my $prereq = Pakket::Requirement->new(
                'category' => $prereq_category,
                'name'     => $prereq_name,
                'version'  => $prereq_version,
                'release'  => $prereq_release,
            );

            $self->install_package(
                $prereq, $dir,
                { %{$opts}, 'as_prereq' => 1 },
            );
        }
    }

    foreach my $item ( $full_parcel_dir->children ) {
        my $basename = $item->basename;

        $basename eq PARCEL_METADATA_FILE()
            and next;

        my $target_dir = $dir->child($basename);
        dircopy( $item, $target_dir );
    }

    Pakket::InfoFile::add_package( $parcel_dir, $dir, $full_package, $opts );

    log_success( sprintf 'Delivering parcel %s', $full_package->full_name );

    return;
}

__PACKAGE__->meta->make_immutable;

no Moose;

1;

__END__

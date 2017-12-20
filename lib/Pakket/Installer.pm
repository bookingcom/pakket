package Pakket::Installer;
# ABSTRACT: Install pakket packages into an installation directory

use Moose;
use MooseX::StrictConstructor;
use Carp                  qw< croak >;
use Path::Tiny            qw< path  >;
use Types::Path::Tiny     qw< Path  >;
use File::Copy::Recursive qw< dircopy >;
use Time::HiRes           qw< time >;
use Log::Any              qw< $log >;
use JSON::MaybeXS         qw< decode_json >;
use Archive::Any;
use English               qw< -no_match_vars >;

use Pakket::Repository::Parcel;
use Pakket::Package;
use Pakket::PackageQuery;
use Pakket::Log       qw< log_success log_fail >;
use Pakket::Types     qw< PakketRepositoryBackend >;
use Pakket::Utils     qw< is_writeable >;
use Pakket::Constants qw<
    PARCEL_METADATA_FILE
    PARCEL_FILES_DIR
>;

with qw<
    Pakket::Role::HasConfig
    Pakket::Role::HasParcelRepo
    Pakket::Role::HasInfoFile
    Pakket::Role::HasLibDir
    Pakket::Role::RunCommand
>;

has 'force' => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'default' => sub {0},
);

has 'requirements' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'default' => sub { +{} },
);

has 'ignore_failures' => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'default' => sub {0},
);

sub install {
    my ( $self, @packages ) = @_;

    if ( !@packages ) {
        $log->notice('Did not receive any parcels to deliver');
        return;
    }

    @packages = $self->set_latest_version_for_undefined(@packages);

    foreach (@packages) { $self->requirements->{$_->short_name} = $_ };

    if ( !$self->force ) {
        @packages = $self->drop_installed_packages(@packages);
        @packages or return;
    }

    my $installer_cache = {};

    foreach my $package (@packages) {
        eval {
            $self->install_package(
                $package,
                $self->work_dir,
                { 'cache' => $installer_cache }
            );
            1;
        } or do {
            $self->ignore_failures or die $@;
            $log->warnf( 'Failed to install %s, skipping', $package->full_name);
        };
    }

    $self->activate_work_dir;

    $log->infof(
        "Finished installing %d packages into '%s'",
        scalar keys %{$installer_cache}, $self->pakket_dir,
    );

    log_success( 'Finished installing: ' . join ', ',
        map $_->full_name, @packages );

    $self->remove_old_libraries;

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

    pre_install_checks($dir, $package, $opts);

    $log->debugf( "About to install %s (into $dir)", $package->full_name );

    is_installed($installer_cache, $package)
        and return;

    mark_as_installed($installer_cache, $package);

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

            $self->install_prereq(
                $prereq_category,
                $prereq_name,
                $prereq_data,
                $dir,
                $opts,
            );
        }
    }

    copy_package_to_install_dir($full_parcel_dir, $dir);

    $self->add_package_in_info_file( $parcel_dir, $dir, $full_package, $opts );

    log_success( sprintf 'Delivering parcel %s', $full_package->full_name );

    return;
}

sub install_prereq {
    my ($self, $category, $name, $prereq_data, $dir, $opts) = @_;
    my $package;
    if (exists $self->requirements->{"$category/$name"}) {
        $package = $self->requirements->{"$category/$name"};
        # FIXME: should we check compatibility
        # requested by user version of package
        # with dependencies requirements?
        # if yes, should we disable it by option --force?
    } else {
        # FIXME: This should be removed when we introduce version ranges
        # This forces us to install the latest version we have of
        # something, instead of finding the latest, based on the
        # version range, which "$prereq_version" contains. -- SX
        my $ver_rel = $self->parcel_repo->latest_version_release(
                    $category,
                    $name,
                    $prereq_data->{'version'},
                );

        my ( $version, $release ) = @{$ver_rel};

        $package = Pakket::PackageQuery->new(
                'category' => $category,
                'name'     => $name,
                'version'  => $version,
                'release'  => $release,
                );
    }

    $self->install_package(
        $package, $dir,
        { %{$opts}, 'as_prereq' => 1 },
    );
}

sub copy_package_to_install_dir {
    my ($full_parcel_dir, $dir) = @_;
    foreach my $item ( $full_parcel_dir->children ) {
        my $basename = $item->basename;

        $basename eq PARCEL_METADATA_FILE()
            and next;

        my $target_dir = $dir->child($basename);
        local $File::Copy::Recursive::RMTrgFil = 1;
        dircopy($item, $target_dir)
            or croak($log->criticalf("Can't copy $item to $target_dir ($!)"));
    }
}

sub is_installed {
    my ($installer_cache, $package) = @_;

    my $pkg_cat  = $package->category;
    my $pkg_name = $package->name;

    if ( defined $installer_cache->{$pkg_cat}{$pkg_name} ) {
        my $ver_rel = $installer_cache->{$pkg_cat}{$pkg_name};
        my ( $version, $release ) = @{$ver_rel};

        # Check version
        if ( $version ne $package->version ) {
            croak( $log->criticalf(
                "%s=$version already installed. "
              . "Cannot install new version: %s",
              $package->short_name,
              $package->version,
            ) );
        }

        # Check release
        if ( $release ne $package->release ) {
            croak( $log->criticalf(
                '%s=%s:%s already installed. '
              . 'Cannot install new version: %s:%s',
                $package->short_name,
                $version, $release,
                $package->release,
            ) );
        }

        $log->debugf( '%s already installed.', $package->full_name );

        return 1;
    }

    return 0;
}

sub mark_as_installed {
    my ($installer_cache, $package) = @_;

    my $pkg_cat  = $package->category;
    my $pkg_name = $package->name;

    $installer_cache->{$pkg_cat}{$pkg_name} = [
        $package->version, $package->release,
    ];
}

sub pre_install_checks {
    my ($dir, $package, $opts) = @_;

    # Are we in a regular (non-bootstrap) mode?
    # Are we using a bootstrap version of a package?
    if ( ! $opts->{'skip_prereqs'} && $package->is_bootstrap ) {
        croak( $log->critical(
            'You are trying to install a bootstrap version of %s.'
          . ' Please rebuild this package from scratch.',
            $package->full_name,
        ) );
    }

    if ( !is_writeable($dir) ) {
        croak( $log->critical(
            "Can't write to your installation directory ($dir)",
        ) );
    }
}

sub show_installed {
    my $self = shift;
    my $installed_packages = $self->load_installed_packages($self->active_dir);
    print join("\n", sort keys %{$installed_packages} ) . "\n";
}

sub drop_installed_packages {
    my $self = shift;
    my @packages = @_;
    my $installed_packages = $self->load_installed_packages($self->active_dir);
    my @out;
    for my $package (@packages) {
        if ($installed_packages->{$package->full_name}) {
            $log->infof( '%s already installed', $package->full_name );
        } else {
            push @out, $package;
        }
    }
    return @out;
}

sub set_latest_version_for_undefined {
    my $self      = shift;
    my @packages  = @_;

    my @output;
    for my $package (@packages) {
        if ($package->version && $package->release) {
            push @output, $package;
        } else {
            my $ver_condition = $package->version
                ? "== " . $package->version
                : ">= 0";

            my ($ver, $rel) = @{$self->parcel_repo->latest_version_release(
                                    $package->category, $package->name, $ver_condition)};

            push @output, Pakket::Package->new(
                                'category' => $package->category,
                                'name'     => $package->name,
                                'version'  => $ver,
                                'release'  => $rel,
                            );
        }
    }
    return @output;
}

__PACKAGE__->meta->make_immutable;

no Moose;

1;

__END__

=pod

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head2 config

See L<Pakket::Role::HasConfig>.

=head2 parcel_repo

See L<Pakket::Role::HasParcelRepo>.

=head2 parcel_repo_backend

See L<Pakket::Role::HasParcelRepo>.

=head2 requirements

List in hashref built during install of additional requirements.

=head2 force

A boolean to install packages even if they are already installed.

=head2 pakket_dir

See L<Pakket::Role::HasLibDir>.

=head2 libraries_dir

See L<Pakket::Role::HasLibDir>.

=head2 active_dir

See L<Pakket::Role::HasLibDir>.

=head2 work_dir

See L<Pakket::Role::HasLibDir>.

=head1 METHODS

=head2 activate_work_dir

See L<Pakket::Role::HasLibDir>.

=head2 remove_old_libraries

See L<Pakket::Role::HasLibDir>.

=head2 add_package_in_info_file

See L<Pakket::Role::HasInfoFile>.

=head2 load_info_file

See L<Pakket::Role::HasInfoFile>.

=head2 save_info_file

See L<Pakket::Role::HasInfoFile>.

=head2 load_installed_packages

See L<Pakket::Role::HasInfoFile>.

=head2 install(@packages)

The main method used to install packages.

Installs all packages and then turns on the active directory link.

=head2 try_to_install_package($package, $dir, \%opts)

Attempts to install a package while reporting failure. This is useful
when it is possible to install but might not work. It is used by the
L<Pakket::Builder> to install all possible available pre-built
packages.

=head2 install_package($package, $dir, \%opts)

The guts of installing a package. This is used by C<install> and
C<try_to_install_package>.

=head2 install_prereq($category, $name, \%prereq_data, $dir, \%opts)

Takes a prereq from a package, finds the matching package and installs
it.

=head2 copy_package_to_install_dir($source_dir, $target_dir)

Recursively copy all the package directories and files to the install
directory.

=head2 is_installed(\%installer_cache, $package)

Check whether the package is already installed or not using our
installer cache.

=head2 mark_as_installed(\%installer_cache, $package)

Add to cache as installed.

=head2 pre_install_checks($dir, $package, \%opts)

Perform all the checks for the installation phase.

=head2 show_installed()

Display all the installed packages. This is helpful for debugging.

=head2 drop_installed_packages(@packages)

Removes installed packages from a list of given packages.

=head2 run_command

See L<Pakket::Role::RunCommad>.

=head2 run_command_sequence

See L<Pakket::Role::RunCommad>.

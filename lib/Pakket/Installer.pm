package Pakket::Installer;
# ABSTRACT: Install pakket packages into an installation directory

use v5.22;
use Moose;
use MooseX::StrictConstructor;

use Archive::Any;
use Carp                  qw< croak >;
use English               qw< -no_match_vars >;
use Errno                 qw< :POSIX >;
use File::Copy::Recursive qw< dircopy dirmove >;
use JSON::MaybeXS         qw< decode_json >;
use Log::Any              qw< $log >;
use Path::Tiny            qw< path >;
use Time::HiRes           qw< time usleep >;
use Types::Path::Tiny     qw< Path >;


use Pakket::Repository::Parcel;
use Pakket::Package;
use Pakket::PackageQuery;
use Pakket::Log;
use Pakket::Types     qw< PakketRepositoryBackend >;
use Pakket::Utils     qw< is_writeable >;
use Pakket::Constants qw<
    PARCEL_METADATA_FILE
    PARCEL_FILES_DIR
    PAKKET_PACKAGE_SPEC
>;

use constant {
    'SLEEP_TIME' => 100,
};

with qw<
    Pakket::Role::CanUninstallPackage
    Pakket::Role::HasConfig
    Pakket::Role::HasParcelRepo
    Pakket::Role::HasInfoFile
    Pakket::Role::HasLibDir
    Pakket::Role::RunCommand
    Pakket::Role::ParallelInstaller
>;

has 'force' => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'default' => sub { 0 },
);

has 'silent' => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'default' => sub { 0 },
);

has 'requirements' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'default' => sub { +{} },
);

has 'ignore_failures' => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'default' => sub { 0 },
);

has 'installed_packages' => (
    'is'      => 'rw',
    'isa'     => 'HashRef',
    # Don't load installed_packages in constuctor.
    # Installer is also used by Builder,
    # which doesn't have installed_packages
    'default' => sub { +{} },
);

sub install {
    my ($self, @pack_list) = @_;

    my $_start = time;
    my $result = $self->_do_install(@pack_list);

    Pakket::Log::send_data(
        {
            'severity' => $result ? 'warning' : 'info',
            'type'     => 'install',
            'version'  => "$Pakket::Package::VERSION",
            'count'    => scalar @pack_list,
            'is_force' => $self->force ? 1 : 0,
            'result'   => int($result),
        },
        $_start,
        time(),
    );

    return $result;
}

sub dry_run {
    my ($self, @pack_list) = @_;

    if (!@pack_list) {
        $log->notice('Did not receive any parcels to check');
        return EINVAL;
    }

    $self->{'silent'} = 1;

    my $packages = $self->_preprocess_packages_list(@pack_list);
    @{$packages} or return 0;

    foreach my $package (@{$packages}) {
        $log->info($package->full_name);
    }

    return E2BIG;
}

sub show_installed {
    my ($self) = @_;

    my @installed_packages = map { $_->full_name } values %{$self->load_installed_packages($self->active_dir)};

    print join("\n", sort @installed_packages ) . "\n";

    return 0;
}

sub try_to_install_package {
    my ($self, $package, $dir, $opts) = @_;

    $log->debugf('Trying to install %s', $package->full_name);

    # First we check whether a package exists, because if not
    # we wil throw a silly critical warning about it
    # This can also speed stuff up, but maybe should be put into
    # "has_package" wrapper function... -- SX
    $self->parcel_repo->has_object($package->id)
        or return;

    eval {
        $self->install_package($package, $dir, $opts);
        1;
    } or do {
        $log->debugf('Could not install %s', $package->full_name);
        return;
    };

    return 1;
}

sub install_package {
    my ( $self, $package, $dir, $opts ) = @_;

    my $installer_cache = $opts->{'cache'};

    $self->_pre_install_checks($dir, $package, $opts);

    $log->debugf( "About to install %s (into $dir)", $package->full_name );

    $self->is_installed($installer_cache, $package)
        and return;

    $self->_mark_as_installed($installer_cache, $package);

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

            $self->_install_prereq(
                $prereq_category,
                $prereq_name,
                $prereq_data,
                $dir,
                $opts,
            );
        }
    }

    my $info_file = $self->load_info_file($dir);

    # uninstall previous version of the package
    my $package_to_update = $self->_package_to_upgrade($package);
    if ($package_to_update) {
        $self->uninstall_package($info_file, $package_to_update);
    }

    _copy_package_to_install_dir($full_parcel_dir, $dir);

    $self->add_package_to_info_file( $parcel_dir, $info_file, $full_package, $opts );

    $self->save_info_file($dir, $info_file);

    $log->noticef( 'Delivering parcel %s', $full_package->full_name );

    return;
}

sub _do_install {
    my ( $self, @pack_list ) = @_;

    if (!@pack_list) {
        $log->warning('Did not receive any parcels to deliver');
        return EINVAL;
    }

    if (!$self->force && $self->allow_rollback && $self->rollback_tag) {
        my $tags = $self->_get_rollback_tags();

        if (exists $tags->{$self->rollback_tag}) {
            $log->debugf('Found dir %s with rollback_tag %s', $tags->{$self->rollback_tag}, $self->rollback_tag);
            my $result = $self->activate_dir($tags->{$self->rollback_tag});
            if ($result && $result == EEXIST) {
                $log->notice( 'All packages already installed in active library with tag: ' . $self->rollback_tag );
            } else {
                $log->debug( 'Packages installed: ' . join ', ', map $_->full_name, @pack_list );
                $log->info( 'Finished activating library with tag: ' . $self->rollback_tag );
            }
            return 0;
        }
    }

    if ( !is_writeable($self->work_dir) ) {
        croak($log->criticalf("Can't write to your installation directory (%s)", $self->work_dir));
    }

    my $packages = $self->_preprocess_packages_list(@pack_list);
    @{ $packages } or return 0;

    $self->_check_packages_in_parcel_repo($packages);

    $log->infof('Requested %s parcels', scalar @{ $packages });
    my $installed_count = $self->is_parallel
        ?  $self->_install_packages_parallel($packages)
        :  $self->_install_packages_sequential($packages);

    $self->set_rollback_tag($self->work_dir, $self->rollback_tag);
    $self->activate_work_dir;

    $log->debug( 'Finished installing: ' . join ', ', map $_->full_name, @{ $packages });
    $log->noticef( "Finished installing %d packages into '%s'", $installed_count, $self->pakket_dir->stringify);

    return 0;
}

sub _install_packages_sequential {
    my ( $self, $packages ) = @_;

    my %installer_cache;
    foreach my $package (@{$packages}) {
        eval {
            $self->install_package(
                $package,
                $self->work_dir,
                { 'cache' => \%installer_cache },
            );
            1;
        } or do {
            $self->ignore_failures or croak($@);
            $log->warnf( 'Failed to install %s, skipping', $package->full_name);
        };
    }

    return keys %installer_cache;
}

sub _install_packages_parallel {
    my ($self, $packages) = @_;

    $self->push_to_data_consumer($_->full_name) for @{$packages};

    $self->spawn();

    $self->is_child and $self->reset_parcel_backend();

    $self->_fetch_all_packages();

    $self->wait_all_children();

    $self->_check_parcels_fetched();

    my $installed_count = $self->_install_all_packages();

    return $installed_count;
}

sub _fetch_all_packages {
    my ($self) = @_;

    my $dir = $self->work_dir;
    my $dc_dir = $self->data_consumer_dir;
    my $failure_dir = $self->data_consumer_dir->child('failed');

    $self->data_consumer->consume(sub {
        my ($consumer, $other_spec, $fh, $file) = @_;

        if (!$self->ignore_failures && $failure_dir->children) {
            $consumer->halt;
            $log->critical('Halting job early, some parcels cannot be fetched');
        }

        my $file_contents = <$fh>;
        if (!$file_contents) {
            $log->infof('Another worker got hold of the lock for %s first -- skipping', $file);
            return $consumer->leave;
        }

        my $package_str = substr $file_contents, 1;

        my ( $pkg_cat, $pkg_name, $pkg_version, $pkg_release ) = $package_str =~ PAKKET_PACKAGE_SPEC();

        my $package = Pakket::Package->new(
            'category' => $pkg_cat,
            'name'     => $pkg_name,
            'version'  => $pkg_version // 0,
            'release'  => $pkg_release // 0,
        );

        $self->_pre_install_checks( $dir, $package, {} );

        $log->infof( 'Fetching %s', $package->full_name );

        $self->is_installed({}, $package)
            and return;

        my $parcel_dir = $self->parcel_repo->retrieve_package_parcel($package);

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

                my $p = $self->_get_prereq( $prereq_category, $prereq_name, $prereq_data );
                if (not exists $self->installed_packages->{$p->short_name} ) {
                    $self->push_to_data_consumer( $p->full_name, { 'as_prereq' => 1 } );
                }
            }
        }

        dirmove( $parcel_dir, $dc_dir->child( 'to_install' => $file ) )
            or croak $!;

        # It's actually faster to not hammer the filesystem checking for new
        # stuff. $consumer->consume will continue until `unprocessed` is empty,
        # so it's useful to wait a bit (100ms) to wait for new items to be added.
        usleep SLEEP_TIME();
    });

    my $stats = $self->data_consumer->runstats();
    return $stats->{'failed'};
}

sub _check_parcels_fetched {
    my ($self) = @_;

    my $failure_dir = $self->data_consumer_dir->child('failed');
    my @failed = $self->data_consumer_dir->child('failed')->children;
    if (!$self->ignore_failures && @failed) {
        foreach my $file (@failed) {
            my $package_str = substr $file->slurp, 1;
            $log->criticalf('Unable to fetch %s', $package_str);
        }
        croak($log->criticalf('Unable to fetch %d parcels', scalar @failed));
    }
}

sub _install_all_packages {
    my ($self) = @_;

    my $installed_count = 0;

    my $dir = $self->work_dir;
    my $dc_dir = $self->data_consumer_dir;

    my $info_file = $self->load_info_file($dir);
    $dc_dir->child('processed')->visit(sub {
        my ($file, $state) = @_;

        read $file->filehandle, my $as_prereq, 1
            or croak( $log->criticalf( "Couldn't read %s", $file->absolute ) );
        $as_prereq eq '0' || $as_prereq eq '1'
            or croak( $log->criticalf( 'Unexpected contents on %s: %s', $file->absolute, $file->slurp ) );

        my $parcel_dir = $dc_dir->child('to_install' => $file->basename);
        if ($parcel_dir->exists) {
            my $full_parcel_dir = $parcel_dir->child( PARCEL_FILES_DIR() );

            # Get the spec and create a new Package object
            # This one will have the dependencies as well
            my $spec_file = $full_parcel_dir->child( PARCEL_METADATA_FILE() );
            my $spec      = decode_json $spec_file->slurp_utf8;
            my $package   = Pakket::Package->new_from_spec($spec);

            # uninstall previous version of the package
            my $package_to_update = $self->_package_to_upgrade($package);
            if ($package_to_update) {
                $self->uninstall_package($info_file, $package_to_update);
            }

            _copy_package_to_install_dir($full_parcel_dir, $dir);

            $self->add_package_to_info_file( $parcel_dir, $info_file, $package, { 'as_prereq' => $as_prereq } );

            $log->noticef( 'Delivering parcel %s', $package->full_name );

            $installed_count++;
        }
    });
    $self->save_info_file($dir, $info_file);

    $dc_dir->remove_tree({'safe' => 0});

    return $installed_count;
}

sub _get_prereq {
    my ($self, $category, $name, $prereq_data) = @_;
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

        $package = Pakket::Package->new(
                'category' => $category,
                'name'     => $name,
                'version'  => $version,
                'release'  => $release,
                );
    }

    return $package;
}

## no critic (Perl::Critic::Policy::Subroutines::ProhibitManyArgs)
sub _install_prereq {
    my ($self, $category, $name, $prereq_data, $dir, $opts) = @_;

    my $package = $self->_get_prereq($category, $name, $prereq_data);
    $self->install_package($package, $dir, {%{$opts}, 'as_prereq' => 1});
}

sub _copy_package_to_install_dir {
    my ($full_parcel_dir, $dir) = @_;

    foreach my $item ($full_parcel_dir->children) {
        my $basename = $item->basename;

        $basename eq PARCEL_METADATA_FILE()
            and next;

        my $target_dir = $dir->child($basename);
        ## no critic (Perl::Critic::Policy::Variables::ProhibitPackageVars)
        local $File::Copy::Recursive::RMTrgFil = 1;
        dircopy($item, $target_dir)
            or croak($log->criticalf("Can't copy $item to $target_dir ($!)"));
    }
}

sub _package_to_upgrade {
    my ($self, $package) = @_;

    my $installed_package = $self->installed_packages->{$package->short_name};
    if ($installed_package) {
        if ($installed_package && $installed_package->full_name eq $package->full_name) {
            $log->infof('%s is going to be reinstalled', $installed_package->full_name);
        } else {
            $log->infof('%s is going to be upgraded to %s', $installed_package->full_name, $package->full_name);
        }
        return $installed_package;
    }
    return;
}

sub is_installed {
    my ($self, $installer_cache, $package) = @_;

    my $installed_package = $self->installed_packages->{$package->short_name};
    if (!$self->force && $installed_package && $installed_package->full_name eq $package->full_name) {
        $log->debugf('%s already installed', $package->full_name);
        return 1;
    }

    my $pkg_cat  = $package->category;
    my $pkg_name = $package->name;

    if ( defined $installer_cache->{$pkg_cat}{$pkg_name} ) {
        my $ver_rel = $installer_cache->{$pkg_cat}{$pkg_name};
        my ( $version, $release ) = @{$ver_rel};

        # Check version
        if ( $version ne $package->version ) {
            croak( $log->criticalf(
                "%s=$version already installed. "
              . 'Cannot install new version: %s',
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

sub _mark_as_installed {
    my ($self, $installer_cache, $package) = @_;

    my $pkg_cat  = $package->category;
    my $pkg_name = $package->name;

    $installer_cache->{$pkg_cat}{$pkg_name} = [
        $package->version, $package->release,
    ];
}

sub _pre_install_checks {
    my ($self, $dir, $package, $opts) = @_;

    # Are we in a regular (non-bootstrap) mode?
    # Are we using a bootstrap version of a package?
    if ( ! $opts->{'skip_prereqs'} && $package->is_bootstrap ) {
        croak( $log->critical(
            'You are trying to install a bootstrap version of %s.'
          . ' Please rebuild this package from scratch.',
            $package->full_name,
        ) );
    }
}

sub _filter_packages {
    my ($self, @packages) = @_;

    my @result;
    for my $package (@packages) {
        my $installed_package = $self->installed_packages->{$package->short_name};
        if ($installed_package) {
            if ($installed_package->full_name ne $package->full_name) {
                push @result, $package;
            } elsif ($self->force) {
                $self->silent or $log->infof('%s already installed, but enabled --force, reinstalling it', $package->full_name);
                push @result, $package;
            }
        } else {
            push @result, $package;
        }
    }
    if (!@result && !$self->silent) {
        if (0+@packages == 1) {
            $log->noticef('%s already installed', $packages[0]->full_name);
        } else {
            $log->notice('All packages are already installed');
        }
    }
    return @result;
}

sub _preprocess_packages_list {
    my ($self, @packages) = @_;

    @packages or return \@packages;

    @packages = $self->_set_latest_version_for_undefined(@packages);

    foreach (@packages) { $self->requirements->{$_->short_name} = $_ }

    $self->installed_packages($self->load_installed_packages($self->active_dir));

    @packages = $self->_filter_packages(@packages);

    return \@packages;
}

sub _set_latest_version_for_undefined {
    my ($self, @packages) = @_;

    my @output;
    foreach my $package (@packages) {
        if ($package->version && $package->release) {
            push @output, $package;
        } else {
            my $ver_condition = $package->version
                ? '== ' . $package->version
                : '>= 0';

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

sub _check_packages_in_parcel_repo {
    my ($self, $packages) = @_;
    my %all = map {$_=>1} @{$self->parcel_repo->all_object_ids()};
    for my $package ( @{$packages} ) {
        if (!$all{$package->id} && !$self->parcel_repo->has_object($package->id)) {
            local $! = ENOENT;
            croak($log->criticalf('Package %s doesn\'t exist in parcel repo', $package->id));
        }
    }
}

sub _get_rollback_tags {
    my ($self) = @_;

    my @dirs = grep {
        $_->basename ne 'active' && $_->is_dir
    } $self->libraries_dir->children;

    my $result = {};
    foreach my $dir (@dirs) {
        my $tag = $self->get_rollback_tag($dir);
        $tag or next;
        $result->{$tag} = $dir;
    }

    return $result;
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

=head2 add_package_to_info_file

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

=head2 _install_prereq($category, $name, \%prereq_data, $dir, \%opts)

Takes a prereq from a package, finds the matching package and installs
it.

=head2 _copy_package_to_install_dir($source_dir, $target_dir)

Recursively copy all the package directories and files to the install
directory.

=head2 is_installed(\%installer_cache, $package)

Check whether the package is already installed or not using our
installer cache.

=head2 _mark_as_installed(\%installer_cache, $package)

Add to cache as installed.

=head2 _pre_install_checks($dir, $package, \%opts)

Perform all the checks for the installation phase.

=head2 show_installed()

Display all the installed packages. This is helpful for debugging.

=head2 run_command

See L<Pakket::Role::RunCommad>.

=head2 run_command_sequence

See L<Pakket::Role::RunCommad>.

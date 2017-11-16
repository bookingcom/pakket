package Pakket::Builder;
# ABSTRACT: Build pakket packages

use Moose;
use MooseX::StrictConstructor;
use Carp                      qw< croak >;
use Path::Tiny                qw< path        >;
use File::Copy::Recursive     qw< dircopy     >;
use Algorithm::Diff::Callback qw< diff_hashes >;
use Types::Path::Tiny         qw< Path >;
use Log::Any                  qw< $log >;
use version 0.77;

use Pakket::Log qw< log_success log_fail >;
use Pakket::Package;
use Pakket::PackageQuery;
use Pakket::Bundler;
use Pakket::Installer;
use Pakket::Builder::NodeJS;
use Pakket::Builder::Perl;
use Pakket::Builder::Native;

use Pakket::Utils qw< generate_env_vars >;

use constant {
    'BUILD_DIR_TEMPLATE' => 'BUILD-XXXXXX',
};

with qw<
    Pakket::Role::HasConfig
    Pakket::Role::HasSpecRepo
    Pakket::Role::HasSourceRepo
    Pakket::Role::HasParcelRepo
    Pakket::Role::Perl::BootstrapModules
    Pakket::Role::RunCommand
>;

has 'build_dir' => (
    'is'      => 'ro',
    'isa'     => Path,
    'coerce'  => 1,
    'lazy'    => 1,
    'default' => sub {
        return Path::Tiny->tempdir(
            BUILD_DIR_TEMPLATE(),
            'CLEANUP' => 0,
        );
    },
);

has 'keep_build_dir' => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'default' => sub {0},
);

has 'is_built' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'default' => sub { +{} },
);

has 'build_files_manifest' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'default' => sub { +{} },
);

has 'builders' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'default' => sub {
        return {
            'nodejs' => Pakket::Builder::NodeJS->new(),
            'perl'   => Pakket::Builder::Perl->new(),
            'native' => Pakket::Builder::Native->new(),
        };
    },
);

has 'bundler' => (
    'is'      => 'ro',
    'isa'     => 'Pakket::Bundler',
    'lazy'    => 1,
    'builder' => '_build_bundler',
);

has 'installer' => (
    'is'      => 'ro',
    'isa'     => 'Pakket::Installer',
    'lazy'    => 1,
    'default' => sub {
        my $self = shift;

        return Pakket::Installer->new(
            'pakket_dir'  => $self->build_dir,
            'parcel_repo' => $self->parcel_repo,
        );
    },
);

has 'installer_cache' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'default' => sub { +{} },
);

has 'bootstrapping' => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'default' => 1,
);

has 'requirements' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'default' => sub { +{} },
);

sub _build_bundler {
    my $self = shift;

    return Pakket::Bundler->new(
        'parcel_repo' => $self->parcel_repo,
    );
}

sub build {
    my ( $self, @requirements ) = @_;
    my %categories = map +( $_->category => 1 ), @requirements;

    $self->_setup_build_dir;

    if ( $self->bootstrapping ) {
        foreach my $category ( keys %categories ) {
            $self->bootstrap_build($category);
            log_success('Bootstrapping');
        }
    }

    foreach my $requirement (@requirements ) {
        $self->run_build($requirement);
    }
}

sub DEMOLISH {
    my $self      = shift;
    my $build_dir = $self->build_dir;

    if ( !$self->keep_build_dir ) {
        $log->debug("Removing build dir $build_dir");

        # "safe" is false because it might hit files which it does not have
        # proper permissions to delete (example: ZMQ::Constants.3pm)
        # which means it won't be able to remove the directory
        $build_dir->remove_tree( { 'safe' => 0 } );
    }

    return;
}

sub _setup_build_dir {
    my $self = shift;

    $log->debugf( 'Creating build dir %s', $self->build_dir->stringify );
    my $prefix_dir = $self->build_dir->child('main');

    $prefix_dir->is_dir or $prefix_dir->mkpath;

    return;
}

sub bootstrap_build {
    my ( $self, $category ) = @_;

    my @dists =
        $category eq 'perl' ? @{ $self->perl_bootstrap_modules } :
        # add more categories here
        ();

    @dists or return;

    ## no critic qw(BuiltinFunctions::ProhibitComplexMappings Lax::ProhibitComplexMappings::LinesNotStatements)
    my %dist_reqs = map {;
        my $name    = $_;
        my $ver_rel = $self->spec_repo->latest_version_release(
            $category, $name,
        );
        my ( $version, $release ) = @{$ver_rel};

        $name => Pakket::PackageQuery->new(
            'name'     => $name,
            'category' => $category,
            'version'  => $version,
            'release'  => $release,
        );
    } @dists;

    foreach my $dist_name ( @dists ) {
        my $dist_req = $dist_reqs{$dist_name};

        $self->parcel_repo->has_object($dist_req->id)
            or next;

        $log->debugf(
            'Skipping: parcel %s already exists',
            $dist_req->full_name,
        );

        delete $dist_reqs{$dist_name};
    }

    @dists = grep { $dist_reqs{$_} } @dists;
    @dists or return;

    # Pass I: bootstrap toolchain - build w/o dependencies
    for my $dist_name ( @dists ) {
        my $dist_req = $dist_reqs{$dist_name};

        $log->debugf( 'Bootstrapping: phase I: %s (%s)',
                       $dist_req->full_name, 'no-deps' );

        $self->run_build(
            $dist_req,
            { 'bootstrapping_1_skip_prereqs' => 1 },
        );
    }

    # Pass II: bootstrap toolchain - build dependencies only
    for my $dist_name ( @dists ) {
        my $dist_req = $dist_reqs{$dist_name};

        $log->debugf( 'Bootstrapping: phase II: %s (%s)',
                       $dist_req->full_name, 'deps-only' );

        $self->run_build(
            $dist_req,
            { 'bootstrapping_2_deps_only' => 1 },
        );
    }

    # Pass III: bootstrap toolchain - rebuild w/ dependencies
    # XXX: Whoa!
    my $bootstrap_builder = ref($self)->new(
        'parcel_repo'    => $self->parcel_repo,
        'spec_repo'      => $self->spec_repo,
        'source_repo'    => $self->source_repo,
        'keep_build_dir' => $self->keep_build_dir,
        'builders'       => $self->builders,
        'installer'      => $self->installer,
        'bootstrapping'  => 0,
    );

    for my $dist_name ( @dists ) {
        my $dist_req = $dist_reqs{$dist_name};

        # remove the temp (no-deps) parcel
        $log->debugf( 'Removing %s (no-deps parcel)',
                       $dist_req->full_name );

        $self->parcel_repo->remove_package_parcel($dist_req);

        # build again with dependencies

        $log->debugf( 'Bootstrapping: phase III: %s (%s)',
                       $dist_req->full_name, 'full deps' );

        $bootstrap_builder->build($dist_req);
    }
}

sub run_build {
    my ( $self, $prereq, $params ) = @_;
    $params //= {};
    my $level             = $params->{'level'}                        || 0;
    my $skip_prereqs      = $params->{'bootstrapping_1_skip_prereqs'} || 0;
    my $bootstrap_prereqs = $params->{'bootstrapping_2_deps_only'}    || 0;
    my $full_name         = $prereq->full_name;

    # FIXME: GH #29
    if ( $prereq->category eq 'perl' ) {
        # XXX: perl_mlb is a MetaCPAN bug
        $prereq->name eq 'perl_mlb' and return;
        $prereq->name eq 'perl'     and return;
    }

    if ( ! $bootstrap_prereqs and defined $self->is_built->{$full_name} ) {
        $log->debug(
            "We already built or building $full_name, skipping...",
        );

        return;
    }

    $self->is_built->{$full_name} = 1;

    $log->infof( '%s Working on %s', '|...' x $level, $prereq->full_name );

    # Create a Package instance from the spec
    # using the information we have on it
    my $package_spec = $self->spec_repo->retrieve_package_spec($prereq);
    my $package      = Pakket::Package->new_from_spec( +{
        %{$package_spec},

        # We are dealing with a version which should not be installed
        # outside of a bootstrap phase, so we're "marking" this package
        'is_bootstrap' => !!$skip_prereqs,
    } );

    my $top_build_dir  = $self->build_dir;
    my $main_build_dir = $top_build_dir->child('main');

    my $installer = $self->installer;

    if ( !$skip_prereqs && !$bootstrap_prereqs ) {
        my $installer_cache = $self->installer_cache;
        my $bootstrap_cache = {
            %{ $self->installer_cache },

            # Phase 3 needs to avoid trying to install
            # the bare minimum toolchain (Phase 1)
            $prereq->category => { $package->name => $package->version },
        };

        my $successfully_installed = $installer->try_to_install_package(
            $package,
            $main_build_dir,
            {
                'cache'        => ( $self->bootstrapping ? $installer_cache : $bootstrap_cache ),
                'skip_prereqs' => $skip_prereqs,
            },
        );

        if ($successfully_installed) {

            # snapshot_build_dir
            $self->snapshot_build_dir( $package, $main_build_dir->absolute, 0 );

            $log->infof( '%s Installed %s', '|...' x $level, $prereq->full_name );

            # sync build cache with our install cache
            # so we do not accidentally build things
            # that were installed in some recursive iteration
            foreach my $category ( sort keys %{$installer_cache} ) {
                foreach my $package_name (
                    keys %{ $installer_cache->{$category} } )
                {
                    my ($ver,$rel) = @{$installer_cache->{$category}{$package_name}};
                    my $pkg = Pakket::PackageQuery->new(
                                        'category' => $category,
                                        'name'     => $package_name,
                                        'version'  => $ver,
                                        'release'  => $rel,
                                    );
                    $self->is_built->{ $pkg->full_name } = 1;

                    # save requirements of dependencies
                    my $spec = $self->spec_repo->retrieve_package_spec($pkg);

                    for my $dep_category ( keys %{$spec->{'Prereqs'}} ) {
                        my $runtime_deps =
                                $spec->{'Prereqs'}{$dep_category}{'runtime'};

                        for my $dep_name (keys %$runtime_deps) {
                            $self->requirements->{$dep_name}{$pkg->short_name} =
                                        $runtime_deps->{$dep_name}{'version'};
                        }
                    }
                }
            }

            return;
        }
    }

    # recursively build prereqs
    # FIXME: GH #74
    if ( $bootstrap_prereqs or ! $skip_prereqs ) {
        foreach my $category ( keys %{ $self->builders } ) {
            $self->_recursive_build_phase( $package, $category, 'configure', $level+1 );
            $self->_recursive_build_phase( $package, $category, 'runtime', $level+1 );
        }
    }

    $bootstrap_prereqs and return; # done building prereqs
    my $package_src_dir
        = $self->source_repo->retrieve_package_source($package);

    $log->debug('Copying package files');

    # FIXME: This shouldn't just be configure flags
    # we should allow the builder to have access to a general
    # metadata chunk which *might* include configure flags
    my %env_vars = generate_env_vars( $top_build_dir, $main_build_dir );
    my $configure_flags = $self->get_configure_flags(
        $package->build_opts->{'configure_flags'},
        { %ENV, %env_vars },
    );
    my $build_flags = $self->get_configure_flags(
        $package->build_opts->{'build_flags'},
        { %ENV, %env_vars },
    );

    if ( my $builder = $self->builders->{ $package->category } ) {
        my $package_dst_dir = $top_build_dir->child(
            'src',
            $package->category,
            $package_src_dir->basename,
        );


        dircopy( $package_src_dir, $package_dst_dir );

        # during coping, dircopy() resets mtime to current time,
        # which breaks 'make' for some native libraries
        # we have to keep original mtime for files from tar archive
        fix_timestamps($package_src_dir, $package_dst_dir);

        $builder->build_package(
            $package->name,
            $package_dst_dir,
            $main_build_dir,
            $configure_flags,
            $build_flags,
        );
    } else {
        croak( $log->criticalf(
            'I do not have a builder for category %s.',
            $package->category,
        ) );
    }

    my $package_files = $self->snapshot_build_dir(
        $package, $main_build_dir,
    );

    $log->infof( '%s Bundling %s', '|...' x $level, $package->full_name );
    $self->bundler->bundle(
        $main_build_dir->absolute,
        $package,
        $package_files,
    );

    $log->infof( '%s Finished on %s', '|...' x $level, $prereq->full_name );
    log_success( sprintf 'Building %s', $prereq->full_name );

    return;
}

sub fix_timestamps {
    my ($src_dir, $dst_dir) = @_;
    $src_dir->visit(
        sub {
            my $src = shift;
            my $dst = path($dst_dir, $src->relative($src_dir));
            $dst->touch( $src->stat->mtime );
        },
        { recurse => 1 }
    );
}

sub _recursive_build_phase {
    my ( $self, $package, $category, $phase, $level ) = @_;
    my @prereqs = keys %{ $package->prereqs->{$category}{$phase} };

    foreach my $prereq_name (@prereqs) {
        $self->requirements->{$prereq_name}{$package->short_name} =
            $package->prereqs->{$category}{$phase}{$prereq_name}{'version'};

        my $prereq_ver_req = join(",",
                                values %{$self->requirements->{$prereq_name}});

        my $ver_rel = $self->spec_repo->latest_version_release(
            $category, $prereq_name, $prereq_ver_req,
        );

        my ( $version, $release ) = @{$ver_rel};

        my $req = Pakket::PackageQuery->new(
            'category' => $category,
            'name'     => $prereq_name,
            'version'  => $version,
            'release'  => $release,
        );

        $self->run_build( $req, { 'level' => $level } );
    }
}

sub snapshot_build_dir {
    my ( $self, $package, $main_build_dir, $error_out ) = @_;
    $error_out //= 1;

    $log->debug('Scanning directory.');

    # XXX: this is just a bit of a smarter && dumber rsync(1):
    # rsync -qaz BUILD/main/ output_dir/
    # the reason is that we need the diff.
    # if you can make it happen with rsync, remove all of this. :P
    # perhaps rsync(1) should be used to deploy the package files
    # (because then we want *all* content)
    # (only if unpacking it directly into the directory fails)
    my $package_files = $self->retrieve_new_files($main_build_dir);

    if ($error_out) {
        keys %{$package_files}
            or croak( $log->criticalf(
                'This is odd. %s build did not generate new files. '
                    . 'Cannot package.',
                $package->full_name,
            ) );
    }

    # store per all packages to get the diff
    @{ $self->build_files_manifest }{ keys( %{$package_files} ) }
        = values %{$package_files};

    return $self->normalize_paths($package_files);
}

sub normalize_paths {
    my ( $self, $package_files ) = @_;
    my $paths;
    for my $path_and_timestamp (keys %$package_files) {
        my ($path) = $path_and_timestamp =~ /^(.+)_\d+?$/;
        $paths->{$path} = $package_files->{$path_and_timestamp};
    }
    return $paths;
}

sub retrieve_new_files {
    my ( $self, $build_dir ) = @_;

    my $nodes = $self->_scan_directory($build_dir);
    my $new_files
        = $self->_diff_nodes_list( $self->build_files_manifest, $nodes, );

    return $new_files;
}

sub _scan_directory {
    my ( $self, $dir ) = @_;

    my $visitor = sub {
        my ( $node, $state ) = @_;

        return if $node->is_dir;

        my $path_and_timestamp = sprintf("%s_%s",$node->absolute, $node->stat->ctime);

        # save the symlink path in order to symlink them
        if ( -l $node ) {
            path( $state->{ $path_and_timestamp } = readlink $node )->is_absolute
                and croak( $log->critical(
                    "Error. Absolute path symlinks aren't supported.",
                ) );
        } else {
            $state->{ $path_and_timestamp } = '';
        }
    };

    return $dir->visit(
        $visitor,
        { 'recurse' => 1, 'follow_symlinks' => 0 },
    );
}

# There is a possible micro optimization gain here
# if we diff and copy in the same loop
# instead of two steps
sub _diff_nodes_list {
    my ( $self, $old_nodes, $new_nodes ) = @_;

    my %nodes_diff;
    diff_hashes(
        $old_nodes,
        $new_nodes,
        'added'   => sub { $nodes_diff{ $_[0] } = $_[1] },
    );

    return \%nodes_diff;
}

sub get_configure_flags {
    my ( $self, $config, $expand_env ) = @_;

    $config or return [];

    my @flags = @{$config};

    $self->_expand_flags_inplace( \@flags, $expand_env );

    return \@flags;
}

sub _expand_flags_inplace {
    my ( $self, $flags, $env ) = @_;

    for my $flag ( @{$flags} ) {
        for my $key ( keys %{$env} ) {
            my $placeholder = '%' . uc($key) . '%';
            $flag =~ s/$placeholder/$env->{$key}/gsm;
        }
    }

    return;
}

__PACKAGE__->meta->make_immutable;

no Moose;

1;

__END__

=pod

=head1 SYNOPSIS

    use Pakket::Builder;
    my $builder = Pakket::Builder->new();
    $builder->build('perl/Dancer2=0.205000');

=head1 DESCRIPTION

The L<Pakket::Builder> is in charge of building a Pakket package. It is
normally accessed with the C<pakket install> command. Please see
L<pakket> for the command line interface. Specifically
L<Pakket::CLI::Command::install> for the C<install> command
documentation.

The building includes bootstrapping any toolchain systems (currently
only applicable to Perl) and then building all packages specifically.

The installer (L<Pakket::Installer>) can be used to install pre-built
packages.

Once the building is done, the files and their manifest is sent to the
bundler (L<Pakket::Bundler>) in order to create the final parcel. The
parcel will be stored in the appropriate storage, based on your
configuration.

=head1 ATTRIBUTES

=head2 bootstrapping

A boolean indiciating if we want to bootstrap.

Default: B<1>.

=head2 build_dir

The directory in which we build the packages.

Default: A temporary build directory in your temp dir.

=head2 build_files_manifest

After building, the list of built files are stored in this hashref.

=head2 builders

A hashref of available builder classes.

Currently, L<Pakket::Builder::Native>, L<Pakket::Builder::Perl>, and
L<Pakket::Builder::NodeJS>.

=head2 bundler

The L<Pakket::Bundler> object used for creating the parcel from the
built files.

=head2 config

A configuration hashref populated by L<Pakket::Config> from the config file.

Read more at L<Pakket::Role::HasConfig>.

=head2 installer

The L<Pakket::Installer> object used for installing any pre-built
parcels during the build phase.

=head2 installer_cache

A cache for the installer to prevent installation loops.

=head2 is_built

A cache for the built packages for the builder to prevent a loop
during the build phase.

=head2 keep_build_dir

A boolean that controls whether the build dir will be deleted or
not. This is useful for debugging.

Default: B<0>.

=head2 perl_bootstrap_modules

See L<Pakket::Role::Perl::BootstrapModules>.

=head2 parcel_repo

See L<Pakket::Role::HasParcelRole>.

=head2 parcel_repo_backend

See L<Pakket::Role::HasParcelRole>.

=head2 source_repo

See L<Pakket::Role::HasSourceRole>.

=head2 source_repo_backend

See L<Pakket::Role::HasSourceRole>.

=head2 spec_repo

See L<Pakket::Role::HasSpecRole>.

=head2 spec_repo_backend

See L<Pakket::Role::HasSpecRole>.

=head2 requirements

A hashref in which we store the requirements for further building
during the build phase.

=head1 METHODS

=head2 run_command

See L<Pakket::Role::RunCommand>.

=head2 run_command_sequence

See L<Pakket::Role::RunCommand>.

=head2 bootstrap_build($category)

Build all the packages to bootstrap a build environment. This would
include any toolchain packages necessary.

    $builder->bootstrap_build('perl');

This procedure requires three steps:

=over 4

=item 1.

First, we build the bootstrapping packages within the context of the
builder. However, they will depend on any libraries or applications
already available in the current environment. For example, in a Perl
environment, it will use core modules available with the existing
interpreter.

They will need to be built without any dependencies. Since they assume
on the available dependencies in the system, they will build
succesfully.

=item 2.

Secondly, we build their dependencies only. This will allow us to then
build on top of them the original bootstrapping modules, thus
separating them from the system entirely.

=item 3.

Lastly, we repeat the first step, except with dependencies, and
explicitly preferring the dependencies we built at step 2.

=back

=head2 build(@pkg_queries)

The main method of the class. Sets up the bootstrapping and calls
C<run_build>.

    my $pkg_query = Pakket::PackageQuery->new(...);
    $builder->build($pkg_query);

See L<Pakket::PackageQuery> on defining a query for a package.

=head2 get_configure_flags(\%configure_flags, \%env)

This method generates the configure flags for a given package from its
configuration.

=head2 normalize_paths(\%package_files);

Given a set of paths and timestamps, returns a new hashref with
normalized paths.

=head2 retrieve_new_files($build_dir)

Once a build has finished, we attempt to install the directory to a
controlled environment. This method scans that directory to find any
new files generated. This is determined to get packaged in the parcel.

=head2 run_build($pkg_query, \%params)

You should not be calling this function directly.

The guts of the class. Builds an available package and all of its
dependencies recursively.

    my $pkg_query = Pakket::PackageQuery->new(...);

    $builder->run_build(
        $pkg_query,
        {%parameters},
    );

See L<Pakket::PackageQuery> on defining a query for a package.

The method receives a single package query object and a hashref of
parameters.

=over 4

=item * level

This helps with debugging.

=item * bootstrapping_1_skip_prereqs

An indicator of phase 1 of boostrapping.

=item * boostrapping_2_deps_only

An indicator of phase 2 of boostrapping.

=back

=head2 snapshot_build_dir( $package, $build_dir, $error_out )

This method generates the manifest list for the parcel from the scanned
files.

=head2 DEMOLISH

Clean up phase, provided by L<Moose>, used to remove the build
directory if C<keep_build_dir> is false.

Do not call directly.

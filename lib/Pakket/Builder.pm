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
        $category eq 'perl' ? map { $_->[1] } @{ $self->perl_bootstrap_modules } :
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
                    $self->is_built->{"$category/$package_name=$ver:$rel"} = 1;
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
    my $configure_flags = $self->get_configure_flags(
        $package->build_opts->{'configure_flags'},
        { %ENV, generate_env_vars( $top_build_dir, $main_build_dir ) },
    );

    if ( my $builder = $self->builders->{ $package->category } ) {
        my $package_dst_dir = $top_build_dir->child(
            'src',
            $package->category,
            $package_src_dir->basename,
        );


        dircopy( $package_src_dir, $package_dst_dir );

        $builder->build_package(
            $package->name,
            $package_dst_dir,
            $main_build_dir,
            $configure_flags,
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

sub _recursive_build_phase {
    my ( $self, $package, $category, $phase, $level ) = @_;
    my @prereqs = keys %{ $package->prereqs->{$category}{$phase} };

    foreach my $prereq_name (@prereqs) {
        my $prereq_ver_req =
            $package->prereqs->{$category}{$phase}{$prereq_name}{'version'};

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
        my ($path,$timespamp) = $path_and_timestamp =~ /^(.+)_(\d+?)$/;
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

    my @flags = map +( join '=', $_, $config->{$_} ), keys %{$config};

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

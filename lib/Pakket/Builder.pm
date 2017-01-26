package Pakket::Builder;
# ABSTRACT: Build pakket packages

use Moose;
use MooseX::StrictConstructor;
use JSON::MaybeXS             qw< decode_json >;
use List::Util                qw< first       >;
use Path::Tiny                qw< path        >;
use File::Find                qw< find        >;
use File::Copy::Recursive     qw< dircopy     >;
use File::Basename            qw< basename dirname >;
use Algorithm::Diff::Callback qw< diff_hashes >;
use Types::Path::Tiny         qw< Path >;
use TOML::Parser;
use Log::Any                  qw< $log >;
use version 0.77;

use Pakket::Log;
use Pakket::Package;
use Pakket::Bundler;
use Pakket::Installer;
use Pakket::Requirement;
use Pakket::ConfigReader;
use Pakket::Builder::NodeJS;
use Pakket::Builder::Perl;
use Pakket::Builder::Native;
use Pakket::Repository::Config;
use Pakket::Repository::Parcel;
use Pakket::Repository::Source;

use Pakket::Constants   qw< PARCEL_FILES_DIR PAKKET_PACKAGE_SPEC >;
use Pakket::Utils       qw< generate_env_vars >;
use Pakket::Utils::Perl qw< list_core_modules >;

use constant {
    'ALL_PACKAGES_KEY'   => '',
    'BUILD_DIR_TEMPLATE' => 'BUILD-XXXXXX',
};

with 'Pakket::Role::RunCommand';

has 'parcel_dir' => (
    'is'       => 'ro',
    'isa'      => Path,
    'coerce'   => 1,
    'required' => 1,
);

has 'parcel_repo' => (
    'is'      => 'ro',
    'isa'     => 'Pakket::Repository::Parcel',
    'lazy'    => 1,
    'builder' => '_build_parcel_repo',
);

has 'source_repo' => (
    'is'      => 'ro',
    'isa'     => 'Pakket::Repository::Source',
    'lazy'    => 1,
    'builder' => '_build_source_repo',
);

has 'config_repo' => (
    'is'      => 'ro',
    'isa'     => 'Pakket::Repository::Config',
    'lazy'    => 1,
    'builder' => '_build_config_repo',
);

has 'config_dir' => (
    'is'       => 'ro',
    'isa'      => Path,
    'coerce'   => 1,
    'required' => 1,
);

has 'source_dir' => (
    'is'       => 'ro',
    'isa'      => Path,
    'coerce'   => 1,
    'required' => 1,
);

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

has 'bundler_args' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'default' => sub { +{} },
);

has 'installer' => (
    'is'      => 'ro',
    'isa'     => 'Pakket::Installer',
    'lazy'    => 1,
    'default' => sub {
        my $self = shift;

        my $parcel_dir = $self->{'parcel_dir'};
        if ( !$parcel_dir ) {
            $log->critical("'bundler_args' do not contain 'bundle_dir'");
            exit 1;
        }

        return Pakket::Installer->new(
            'pakket_dir'  => $self->build_dir,
            'parcel_repo' => $self->parcel_repo,
            'parcel_dir'  => $self->parcel_dir,
        );
    },
);

has 'bootstrapping' => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'default' => 1,
);

# We're starting with a local repo
# # but in the future this will be dictated from a configuration
sub _build_parcel_repo {
    my $self = shift;

    # Use default for now, but use the directory we want at least
    return Pakket::Repository::Parcel->new(
        'directory' => $self->parcel_dir,
    );
}

# We're starting with a local repo
# # but in the future this will be dictated from a configuration
sub _build_config_repo {
    my $self = shift;

    # Use default for now, but use the directory we want at least
    return Pakket::Repository::Config->new(
        'directory' => $self->config_dir,
    );
}

# We're starting with a local repo
# # but in the future this will be dictated from a configuration
sub _build_source_repo {
    my $self = shift;

    # Use default for now, but use the directory we want at least
    return Pakket::Repository::Source->new(
        'directory' => $self->source_dir,
    );
}

sub _build_bundler {
    my $self = shift;

    return Pakket::Bundler->new(
        %{ $self->bundler_args },
        'parcel_repo' => $self->parcel_repo,
    );
}

sub build {
    my ( $self, $requirement ) = @_;

    $self->_setup_build_dir;
    $self->bootstrapping
        and $self->bootstrap_build( $requirement->category );
    $self->run_build($requirement);
}

sub DEMOLISH {
    my $self      = shift;
    my $build_dir = $self->build_dir;

    if ( !$self->keep_build_dir ) {
        $log->info("Removing build dir $build_dir");

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

    # XXX: Whoa!
    my $bootstrap_builder = ref($self)->new(
        'parcel_dir'     => $self->parcel_dir,
        'config_dir'     => $self->config_dir,
        'source_dir'     => $self->source_dir,
        'keep_build_dir' => $self->keep_build_dir,
        'bundler_args'   => $self->bundler_args,
        'builders'       => $self->builders,
        'installer'      => $self->installer,
        'bootstrapping'  => 0,
    );

    if ( $category eq 'perl' ) {
        # hardcoded list of packages we have to build first
        # using core modules to break cyclic dependencies.
        # we have to maintain the order in order for packages to build
        my @dists = qw<
            ExtUtils-MakeMaker
            Module-Build
            Module-Build-WithXSpp
            Module-Install
        >;

        my %dists;
        my @config_object_ids = @{ $self->config_repo->all_object_ids() };
        my @parcel_object_ids = @{ $self->parcel_repo->all_object_ids() };

        for my $dist (@dists) {
            # Right now everything is pinned so there is only
            # One result. Once the version ranges feature is introduced,
            # we will be able to get the latest version.
            my ($pkg_str) = grep m{^ perl / \Q$dist\E =}xms, @config_object_ids;

            # Create a requirement
            my $req = Pakket::Requirement->new_from_string($pkg_str);
            $dists{ $req->name } = $req->version;
        }

        foreach my $dist_name ( keys %dists ) {
            my $dist_version = $dists{$dist_name};
            my ($has_parcel) = grep
                m{^ perl / \Q$dist_name\E = \Q$dist_version\E $}xms,
                @parcel_object_ids;

            $has_parcel or next;

            $log->noticef( 'Skipping: parcel %s=%s already exists',
                $dist_name, $dist_version );
            @dists = grep +( $_ ne $dist_name ), @dists;
        }

        # Pass I: bootstrap toolchain - build w/o dependencies
        for my $dist_name (@dists) {
            my $dist_version = $dists{$dist_name};

            $log->noticef( 'Bootstrapping: phase I: %s=%s (%s)',
                $dist_name, $dist_version, 'no-deps' );

            # Create a requirement
            my $req = Pakket::Requirement->new(
                'category' => $category,
                'name'     => $dist_name,
                'version'  => $dist_version,
            );

            $self->run_build( $req, { 'bootstrapping_1_skip_prereqs' => 1 } );
        }

        # Pass II: bootstrap toolchain - build dependencies only
        for my $dist_name (@dists) {
            my $dist_version = $dists{$dist_name};

            my $req = Pakket::Requirement->new(
                'category' => $category,
                'name'     => $dist_name,
                'version'  => $dist_version,
            );

            $log->noticef( 'Bootstrapping: phase II: %s (%s)',
                $req->full_name, 'deps-only' );

            $self->run_build( $req, { 'bootstrapping_2_deps_only' => 1 } );
        }

        # Pass III: bootstrap toolchain - rebuild w/ dependencies
        for my $dist_name (@dists) {
            my $dist_version = $dists{$dist_name};

            $log->noticef( 'Bootstrapping: phase III: %s=%s (%s)',
                $dist_name, $dist_version, 'full deps' );

            # remove the temp (no-deps) parcel
            $log->noticef( 'Removing %s=%s (no-deps parcel)',
                $dist_name, $dist_version );

            my $req = Pakket::Requirement->new(
                'category' => $category,
                'name'     => $dist_name,
                'version'  => $dist_version,
            );

            $self->parcel_repo->remove_package_parcel($req);

            # build again with dependencies
            delete $bootstrap_builder->is_built->{ $req->short_name };
            $bootstrap_builder->build($req);
        }
    }
    # elsif ( $category eq ...

    $log->notice('Finished Bootstrapping!');
}

sub run_build {
    my ( $self, $prereq, $params ) = @_;
    $params //= {};
    my $level             = $params->{'level'}                        || 0;
    my $skip_prereqs      = $params->{'bootstrapping_1_skip_prereqs'} || 0;
    my $bootstrap_prereqs = $params->{'bootstrapping_2_deps_only'}    || 0;
    my $short_name        = $prereq->short_name;

    # FIXME: GH #29
    if ( $prereq->category eq 'perl' ) {
        # XXX: perl_mlb is a MetaCPAN bug
        first { $prereq->name eq $_ } qw<perl perl_mlb>
            and return;
    }

    if ( ! $bootstrap_prereqs and defined $self->is_built->{$short_name} ) {
        my $built_version = $self->is_built->{$short_name};

        if ( $built_version ne $prereq->version ) {
            $log->criticalf(
                'Asked to build %s when %s=%s already built',
                $prereq->full_name, $short_name, $built_version,
            );

            exit 1;
        }

        $log->debug(
            "We already built or building $short_name, skipping...",
        );

        return;
    } else {
        $self->is_built->{$short_name} = $prereq->version;
    }

    $log->noticef( '%sWorking on %s', '|...' x $level, $prereq->full_name );

    # Create a Package instance from the configuration
    # using the information we have on it
    my $package_config = $self->config_repo->retrieve_package_config($prereq);
    my $package        = Pakket::Package->new_from_config({
        %{$package_config},

        # We are dealing with a version which should not be installed
        # outside of a bootstrap phase, so we're "marking" this package
        'is_bootstrap' => !!$skip_prereqs,
    });

    my $top_build_dir  = $self->build_dir;
    my $main_build_dir = $top_build_dir->child('main');

    my $installer = $self->installer;

    if ( !$bootstrap_prereqs ) {

        # Use the installer to recursively install all packages
        # that are already available
        $log->debugf( '%s already packaged, unpacking...',
            $package->full_name, );

        my $installer_cache = $self->bootstrapping
            ? {}

            # Phase 3 needs to avoid trying to install
            # the bare minimum toolchain (Phase 1)
            : { $prereq->category => { $package->name => $package->version },
            };

        my $successfully_installed = $installer->try_to_install_package(
            $package,
            $main_build_dir,
            {
                'cache'        => $installer_cache,
                'skip_prereqs' => $skip_prereqs,
            },
        );

        if ($successfully_installed) {

            # snapshot_build_dir
            $self->snapshot_build_dir( $package->category, $package->name,
                $main_build_dir->absolute, 0 );

            $log->noticef(
                '%sInstalled %s',
                '|...' x $level,
                $prereq->full_name,
            );

            return;
        }
    }

    # GH #74
    my @supported_phases = qw< configure runtime >;

    # recursively build prereqs
    if ( $bootstrap_prereqs or ! $skip_prereqs ) {
        foreach my $category ( keys %{ $self->builders } ) {
            $self->_recursive_build_phase( $package, $category, 'configure', $level+1 );
            $self->_recursive_build_phase( $package, $category, 'runtime', $level+1 );
        }
    }

    $bootstrap_prereqs and return; # done building prereqs
    my $package_src_dir
        = $self->source_repo->retrieve_package_source($package);

    $log->info('Copying package files');

    # FIXME: we shouldn't be generating PKG_CONFIG_PATH every time
    #        Instead, set this as default opt and send it to the build
    #        subroutines as "default opts" to add their own stuff to
    #        and add LD_LIBRARY_PATH and PATH to this as well
    my $pkgconfig_path = path( $top_build_dir, qw<main lib pkgconfig> );
    $log->info("Setting PKG_CONFIG_PATH=$pkgconfig_path");
    local $ENV{'PKG_CONFIG_PATH'} = $pkgconfig_path;

    # FIXME: This shouldn't just be configure flags
    # we should allow the builder to have access to a general
    # metadata chunk which *might* include configure flags
    my $configure_flags = $self->get_configure_flags(
        $package->build_opts->{'configure_flags'},
        { %ENV, generate_env_vars( $top_build_dir, $main_build_dir ) },
    );

    # FIXME: $package_dst_dir is dictated from the category
    if ( my $builder = $self->builders->{ $package->category } ) {
        my $package_dst_dir = path(
            $top_build_dir,
            'src',
            $package->category,
            basename($package_src_dir),
        );

        dircopy( $package_src_dir, $package_dst_dir );

        $builder->build_package(
            $package->name,
            $package_dst_dir,
            $main_build_dir,
            $configure_flags,
        );
    } else {
        $log->criticalf(
            'I do not have a builder for category %s.',
            $package->category,
        );
        exit 1;
    }

    my $package_files = $self->snapshot_build_dir(
        $package->category, $package->name, $main_build_dir,
    );

    $log->infof( 'Bundling %s', $package->full_name );
    $self->bundler->bundle(
        $main_build_dir->absolute,
        {
            'category'    => $package->category,
            'name'        => $package->name,
            'version'     => $package->version,
            'bundle_opts' => $package->bundle_opts,
            'config'      => $package->config,
        },
        $package_files,
    );

    $log->noticef(
        '%sFinished on %s', '|...' x $level, $prereq->full_name,
    );

    return;
}

sub _recursive_build_phase {
    my ( $self, $package, $category, $phase, $level ) = @_;
    my @prereqs = keys %{ $package->prereqs->{$category}{$phase} };

    foreach my $prereq_name (@prereqs) {
        # Right now everything is pinned so there is only
        # One result. Once the version ranges feature is introduced,
        # we will be able to get the latest version.
        my ($pkg_str) = grep m{^ \Q$category\E / \Q$prereq_name\E =}xms,
            @{ $self->config_repo->all_object_ids() };

        my $req = Pakket::Requirement->new_from_string($pkg_str);

        $self->run_build( $req, { 'level' => $level } );
    }
}

# FIXME: This subroutine needs to get a package object
sub snapshot_build_dir {
    my ( $self, $category, $package_name, $main_build_dir, $error_out ) = @_;
    $error_out //= 1;

    $log->debug('Scanning directory.');

    # XXX: this is just a bit of a smarter && dumber rsync(1):
    # rsync -qaz BUILD/main/ output_dir/
    # the reason is that we need the diff.
    # if you can make it happen with rsync, remove all of this. :P
    # perhaps rsync(1) should be used to deploy the package files
    # (because then we want *all* content)
    # (only if unpacking it directly into the directory fails)
    my $package_files = $self->retrieve_new_files(
        $category, $package_name, $main_build_dir,
    );

    if ($error_out) {
        keys %{$package_files} or do {
            $log->criticalf(
                'This is odd. %s/%s build did not generate new files. '
                    . 'Cannot package.',
                $category, $package_name,
            );
            exit 1;
        };
    }

    # store per all packages to get the diff
    @{ $self->build_files_manifest }{ keys( %{$package_files} ) }
        = values %{$package_files};

    return $package_files;
}

sub retrieve_new_files {
    my ( $self, $category, $package_name, $build_dir ) = @_;

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

        # save the symlink path in order to symlink them
        if ( -l $node ) {
            path( $state->{ $node->absolute } = readlink $node )->is_absolute
                and $log->critical(
                "Error. Absolute path symlinks aren't supported."), exit 1;
        } else {
            $state->{ $node->absolute } = '';
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
        'deleted' => sub {
            $log->critical(
                "Last build deleted previously existing file: $_[0]");
            exit 1;
        },
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

package Pakket::Builder;
# ABSTRACT: Build pakket packages

use version 0.77;

use Moose;
use JSON::MaybeXS             qw< decode_json >;
use Path::Tiny                qw< path        >;
use File::Find                qw< find        >;
use File::Copy::Recursive     qw< dircopy     >;
use File::Basename            qw< basename dirname >;
use Algorithm::Diff::Callback qw< diff_hashes >;
use Types::Path::Tiny         qw< Path >;
use TOML::Parser;
use Log::Any qw< $log >;

use Pakket::Log;
use Pakket::Bundler;
use Pakket::Installer;
use Pakket::ConfigReader;
use Pakket::Version::Requirements;
use Pakket::Builder::NodeJS;
use Pakket::Builder::Perl;
use Pakket::Builder::System;
use Pakket::Constants qw< PARCEL_FILES_DIR >;

use constant { ALL_PACKAGES_KEY => '', };

with 'Pakket::Role::RunCommand';

has config_dir => (
    is      => 'ro',
    isa     => Path,
    coerce  => 1,
    default => sub { Path::Tiny->cwd },
);

has source_dir => (
    is      => 'ro',
    isa     => Path,
    coerce  => 1,
    default => sub { Path::Tiny->cwd },
);

has build_dir => (
    is      => 'ro',
    isa     => Path,
    coerce  => 1,
    lazy    => 1,
    default => sub { Path::Tiny->tempdir( 'BUILD-XXXXXX', CLEANUP => 0 ) },
);

has keep_build_dir => (
    is      => 'ro',
    isa     => 'Bool',
    default => sub {0},
);

has is_built => (
    is      => 'ro',
    isa     => 'HashRef',
    default => sub { +{} },
);

has build_files_manifest => (
    is      => 'ro',
    isa     => 'HashRef',
    default => sub { +{} },
);

has index_file => (
    is       => 'ro',
    isa      => Path,
    coerce   => 1,
    required => 1,
);

has index => (
    is      => 'ro',
    isa     => 'HashRef',
    lazy    => 1,
    default => sub {
        my $self = shift;
        return decode_json $self->index_file->slurp_utf8;
    },
);

has 'builders' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'default' => sub {
        return {
            'nodejs' => Pakket::Builder::NodeJS->new(),
            'perl'   => Pakket::Builder::Perl->new(),
            'system' => Pakket::Builder::System->new(),
        };
    },
);

has bundler => (
    is      => 'ro',
    isa     => 'Pakket::Bundler',
    lazy    => 1,
    builder => '_build_bundler',
);

has bundler_args => (
    is      => 'ro',
    isa     => 'HashRef',
    default => sub { +{} },
);

has 'installer' => (
    'is'      => 'ro',
    'isa'     => 'Pakket::Installer',
    'lazy'    => 1,
    'default' => sub {
        my $self = shift;

        my $parcel_dir = $self->bundler_args->{'bundle_dir'};
        if ( !$parcel_dir ) {
            $log->critical("'bundler_args' do not contain 'bundle_dir'");
            exit 1;
        }

        return Pakket::Installer->new(
            'pakket_dir' => $self->build_dir,
            'parcel_dir' => $parcel_dir,
            'index'      => $self->index,
            'index_file' => $self->index_file,
        );
    },
);

sub _build_bundler {
    my $self = shift;
    Pakket::Bundler->new( $self->bundler_args );
}

sub build {
    my ( $self, $category, $package, $package_args ) = @_;
    $self->_setup_build_dir;
    $self->run_build( $category, $package, $package_args );
}

sub DEMOLISH {
    my $self      = shift;
    my $build_dir = $self->build_dir;

    if ( !$self->keep_build_dir ) {
        $log->info("Removing build dir $build_dir");

        # "safe" is false because it might hit files which it does not have
        # proper permissions to delete (example: ZMQ::Constants.3pm)
        # which means it won't be able to remove the directory
        path($build_dir)->remove_tree( { safe => 0 } );
    }
}

sub _setup_build_dir {
    my $self = shift;

    $log->debugf( 'Creating build dir %s', $self->build_dir->stringify );
    my $prefix_dir = path( $self->build_dir, 'main' );

    $prefix_dir->is_dir or $prefix_dir->mkpath;
}

sub get_latest_satisfying_version {
    my ( $self, $category, $package_name, $extra ) = @_;

    my $config_file = path( $self->config_dir, $category, $package_name,
        'versioning.toml' );

    my $req;
    if ( -r $config_file ) {
        $log->debug('Using per-package versioning settings');

        $req = $self->_new_requirements_from_config($config_file);
    } else {
        $log->debug('Using category-wide versioning settings');

        $req = $self->_new_requirements_from_category($category);
    }

    $log->debugf( "Package %s uses the '%s' versioning schema",
        $package_name, $req->schema_name );

    my $version = $extra->{'version'} // 0;
    $log->debug("Required: $package_name $version");

    if ( $extra->{'exact_version'} ) {
        $log->debug('Exact version match requested');
        $req->add_exact($version);
    } else {
        $req->add_from_string($version);
    }

    my $chosen = $req->pick_maximum_satisfying_version(
        [ keys %{ $self->index->{$category}{$package_name}{versions} } ] );

    if ( !$chosen ) {
        $log->criticalf(
                "Couldn't find maximum satisfying version for %s in index",
                "$category/$package_name",
        );

        exit 1;
    }
    $log->debug("Chosen: $package_name $chosen");

    return $chosen;
}

sub _new_requirements_from_config {
    my ( $self, $config_file ) = @_;

    my $config_reader = Pakket::ConfigReader->new(
        'type' => 'TOML',
        'args' => [ filename => $config_file ],
    );

    my $config = $config_reader->read_config;

    return Pakket::Version::Requirements->new_from_schema(
        $config->{schema} );
}

sub _new_requirements_from_category {
    my ( $self, $category ) = @_;

    return Pakket::Version::Requirements->new_from_category($category);
}

sub run_build {
    my ( $self, $category, $package_name, $package_args ) = @_;

    my $full_package_name = "$category/$package_name";

    # FIXME: this should be cleaned up as a proper excludes list
    $full_package_name eq 'perl/perl' and return;

    # FIXME: MetaCPAN bug
    $full_package_name eq 'perl/perl_mlb' and return;

    if ( $self->is_built->{$full_package_name}++ ) {
        $log->debug(
            "We already built or building $full_package_name, skipping...");
        return;
    }

    $log->notice("Working on $full_package_name");

    $package_args //= {};

    my $package_version
        = $self->get_latest_satisfying_version( $category, $package_name,
        $package_args );

    $package_version or do {
        $log->critical(
            "Could not find a version number for $full_package_name");
        exit 1;
    };

    my $top_build_dir  = $self->build_dir;
    my $main_build_dir = path( $top_build_dir, 'main' );

    # FIXME: this is a hack
    # Once we have a proper repository, we could query it and find out
    # instead of asking the bundler this
    my $existing_parcel =
        $self->bundler->bundle_dir->child( $category, $package_name,
            "$package_name-$package_version.pkt" );

    if ( $existing_parcel->exists ) {
        # Use the installer to recursively install all packages
        # that are already available
        $log->debug("$full_package_name already packaged, unpacking...");

        my $installer       = $self->installer;
        my $installer_cache = {};

        $installer->install_package(
            "$full_package_name/$package_version",
            $main_build_dir,
            $installer_cache,
        );

        $self->scan_dir( $category, $package_name,
            $main_build_dir->absolute, 0 );

        $self->is_built->{$full_package_name} = 1;

        return;
    }

    my $config = $self->read_package_config(
        $category, $package_name, $package_version,
    ) or return;

    # recursively build prereqs
    # starting with system libraries

    foreach my $type ( keys %{ $self->builders } ) {
        if ( my $prereqs = $config->{'Prereqs'}{$type} ) {
            foreach my $category (qw<configure runtime>) {
                foreach my $prereq ( keys %{ $prereqs->{$category} } ) {
                    $self->run_build( $type, $prereq, $prereqs->{$category}{$prereq} );
                }
            }
        }
    }

    my $package_src_dir = path(
        $self->source_dir,
        $self->index->{$category}{$package_name}{'versions'}{$package_version},
    );

    $log->info('Copying package files');
    -d $package_src_dir or do {
        $log->critical("Cannot find source dir: $package_src_dir");
        exit 1;
    };

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
        $config->{'Package'}{'configure_flags'},
        { main_build_dir => $main_build_dir },
    );

    # FIXME: $package_dst_dir is dictated from the category
    if ( my $builder = $self->builders->{$category} ) {
        my $package_dst_dir = path(
            $top_build_dir,
            'src',
            $category,
            basename($package_src_dir),
        );

        dircopy( $package_src_dir, $package_dst_dir );

        $builder->build_package(
            $package_name,
            $package_dst_dir,
            $main_build_dir,
            $configure_flags,
        );
    } else {
        $log->critical("I do not have a builder for category $category.");
        exit 1;
    }

    $self->is_built->{$full_package_name} = 1;

    my $package_files
        = $self->scan_dir( $category, $package_name, $main_build_dir );

    $log->info("Bundling $full_package_name");
    $self->bundler->bundle(
        $main_build_dir->absolute,
        {
            category => $category,
            name     => $package_name,
            version  => $config->{'Package'}{'version'},
            config   => $config,
        },
        $package_files,
    );
}

sub scan_dir {
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
            $log->critical('This is odd. Build did not generate new files. Cannot package.');
            exit 1;
        };
    }

    # store per all packages to get the diff
    @{ $self->build_files_manifest }{ keys %{$package_files} }
        = values %{$package_files};

    return $package_files;
}

sub retrieve_new_files {
    my ( $self, $category, $package_name, $build_dir ) = @_;

    my $nodes = $self->scan_directory($build_dir);
    my $new_files
        = $self->_diff_nodes_list( $self->build_files_manifest, $nodes, );

    return $new_files;
}

sub scan_directory {
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

    return $dir->visit( $visitor, { recurse => 1, follow_symlinks => 0 } );
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
        added   => sub { $nodes_diff{ $_[0] } = $_[1] },
        deleted => sub {
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

    my @flags;
    for my $tuple ( @{$config} ) {
        if ( @{$tuple} > 2 ) {
            $log->criticalf( 'Odd configuration flag: %s', $tuple );
            exit 1;
        }

        push @flags, join '=', @{$tuple};
    }

    $self->_expand_flags_inplace( \@flags, $expand_env );

    \@flags;
}

sub _expand_flags_inplace {
    my ( $self, $flags, $env ) = @_;

    for my $flag ( @{$flags} ) {
        for my $key ( keys %{$env} ) {
            my $placeholder = '%' . uc($key) . '%';
            $flag =~ s/$placeholder/$env->{$key}/gsm;
        }
    }
}

sub read_package_config {
    my ( $self, $category, $package_name, $package_version ) = @_;

    # FIXME: the config class should have "mandatory" fields, add checks

    # read the configuration
    my $config_file = path( $self->config_dir, $category, $package_name,
        "$package_version.toml" );

    if ( ! -r $config_file ) {
        $log->error("Could not find package information ($config_file)");
        return;
    }

    my $config_reader = Pakket::ConfigReader->new(
        'type' => 'TOML',
        'args' => [ filename => $config_file ],
    );

    my $config = $config_reader->read_config;

    # double check we have the right package configuration
    my $config_name = $config->{'Package'}{'name'};
    if ( !$config_name ) {
        $log->error("Package config must provide 'name'");
        return;
    }

    my $config_category = $config->{'Package'}{'category'};
    if ( !$config_category ) {
        $log->error("Package config must provide 'category'");
        return;
    }

    if ( $config_name ne $package_name ) {
        $log->error("Mismatch package names ($package_name / $config_name)");
        return;
    }

    if ( $config_category ne $category ) {
        $log->error(
            "Mismatch package categories ($category / $config_category)");
        return;
    }

    return $config;
}

__PACKAGE__->meta->make_immutable;

no Moose;

1;

__END__

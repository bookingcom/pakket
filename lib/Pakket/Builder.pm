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
use Pakket::Constants qw< PARCEL_FILES_DIR >;
use Pakket::Utils qw< generate_env_vars >;

use constant {
    'ALL_PACKAGES_KEY'   => '',
    'BUILD_DIR_TEMPLATE' => 'BUILD-XXXXXX',
};

with 'Pakket::Role::RunCommand';

has 'config_dir' => (
    'is'      => 'ro',
    'isa'     => Path,
    'coerce'  => 1,
    'default' => sub { Path::Tiny->cwd },
);

has 'source_dir' => (
    'is'      => 'ro',
    'isa'     => Path,
    'coerce'  => 1,
    'default' => sub { Path::Tiny->cwd },
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

has 'index_file' => (
    'is'       => 'ro',
    'isa'      => Path,
    'coerce'   => 1,
    'required' => 1,
);

has 'index' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'lazy'    => 1,
    'default' => sub {
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
    return Pakket::Bundler->new( $self->bundler_args );
}

sub build {
    my ( $self, %args ) = @_;

    my $prereq = Pakket::Requirement->new(%args);

    $self->_setup_build_dir;
    $self->run_build($prereq);
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

sub run_build {
    my ( $self, $prereq ) = @_;

    # FIXME: GH #29
    if ( $prereq->category eq 'perl' ) {
        # XXX: perl_mlb is a MetaCPAN bug
        first { $prereq->name eq $_ } qw<perl perl_mlb>
            and return;
    }

    if (
        !first { $prereq->version eq $_ }
        @{ $self->versions_in_index($prereq) }
        )
    {
        $log->criticalf(
            'Could not find version %s in index (%s/%s)',
            $prereq->version, $prereq->category, $prereq->name,
        );

        exit 1;
    }

    my $full_name = sprintf '%s/%s', $prereq->category, $prereq->name;
    if ( defined $self->is_built->{$full_name} ) {
        my $built_version = $self->is_built->{$full_name};

        if ( $built_version ne $prereq->version ) {
            $log->criticalf(
                'Asked to build %s=%s when %s=%s already built',
                $full_name, $prereq->version, $full_name, $built_version,
            );

            exit 1;
        }

        $log->debug(
            "We already built or building $full_name, skipping...",
        );

        return;
    } else {
        $self->is_built->{$full_name} = $prereq->version;
    }

    $log->noticef( 'Working on %s=%s', $full_name, $prereq->version );

    # Create a Package instance from the configuration
    # using the information we have on it
    my $package = Pakket::Package->new(
        $self->read_package_config(
            $prereq->category,
            $prereq->name,
            $prereq->version,
        ),
    );

    my $full_package_name = sprintf '%s/%s=%s',
        $package->category, $package->name, $package->version;

    my $category = $package->category;

    my $top_build_dir  = $self->build_dir;
    my $main_build_dir = $top_build_dir->child('main');

    # FIXME: this is a hack
    # Once we have a proper repository, we could query it and find out
    # instead of asking the bundler this
    my $package_name    = $package->name;
    my $existing_parcel = $self->bundler->bundle_dir->child(
        $category,
        $package_name,
        sprintf( '%s-%s.pkt', $package->name, $package->version ),
    );

    my $installer   = $self->installer;
    my $parcel_file = $installer->parcel_file(
        $category, $package_name, $package->version,
    );

    if ( $parcel_file->exists ) {

        # Use the installer to recursively install all packages
        # that are already available
        $log->debug("$full_package_name already packaged, unpacking...");

        my $installer_cache = {};

        $installer->install_package(
            $package,
            $main_build_dir,
            $installer_cache,
        );

        $self->scan_dir( $category, $package_name,
            $main_build_dir->absolute, 0 );

        $log->noticef( 'Installed %s=%s', $full_name, $prereq->version );
        return;
    }

    # GH #74
    my @supported_phases = qw< configure runtime >;

    # recursively build prereqs
    foreach my $category ( keys %{ $self->builders } ) {
        foreach my $supported_phase (@supported_phases) {
            my @prereqs = keys %{ $package->prereqs->{$category}{$supported_phase} };

            foreach my $prereq_name (@prereqs) {
                my $version = $package->prereqs->{$category}{$supported_phase}{$prereq_name}{'version'} //
                    $self->index->{$category}{$prereq_name}{'latest'};

                my $req     = Pakket::Requirement->new(
                    'category' => $category,
                    'name'     => $prereq_name,
                    'version'  => $version,
                );

                $self->run_build($req);
            }
        }
    }

    my $package_src_dir = $self->package_location($package);

    $log->info('Copying package files');
    $package_src_dir->is_dir or do {
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
        $package->build_opts->{'configure_flags'},
        { %ENV, generate_env_vars( $top_build_dir, $main_build_dir ) },
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

    my $package_files = $self->scan_dir(
        $category, $package_name, $main_build_dir,
    );

    $log->info("Bundling $full_package_name");
    $self->bundler->bundle(
        $main_build_dir->absolute,
        {
            'category'    => $category,
            'name'        => $package_name,
            'version'     => $package->version,
            'bundle_opts' => $package->bundle_opts,
            'config'      => $package->config,
        },
        $package_files,
    );

    $log->noticef( 'Finished on %s=%s', $full_name, $prereq->version );

    return;
}

sub versions_in_index {
    my ( $self, $prereq ) = @_;

    my $index    = $self->index;
    my $category = $prereq->category;
    my $name     = $prereq->name;

    if ( !exists $index->{$category}{$name} ) {
        $log->critical("We don't know $category/$name. Sorry.");
        exit 1;
    }

    return [ keys %{ $index->{$category}{$name}{'versions'} } ];
}

sub package_location {
    my ( $self, $package ) = @_;

    my $index   = $self->index;
    my $src_dir = $self->source_dir;

    my $versions
        = $index->{ $package->category }{ $package->name }{'versions'};

    return $src_dir->child( $versions->{ $package->version } );
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
            $log->critical(
                'This is odd. Build did not generate new files. Cannot package.'
            );
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

sub read_package_config {
    my ( $self, $category, $package_name, $package_version ) = @_;

    # FIXME: the config class should have "mandatory" fields, add checks

    # read the configuration
    my $config_file = path( $self->config_dir, $category, $package_name,
        "$package_version.toml" );

    if ( !$config_file->exists ) {
        $log->critical("Could not find package config file: $config_file");
        exit 1;
    }

    if ( !$config_file->is_file ) {
        $log->critical("odd config file: $config_file");
        exit 1;
    }

    my $config_reader = Pakket::ConfigReader->new(
        'type' => 'TOML',
        'args' => [ 'filename' => $config_file ],
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

    my $config_version = $config->{'Package'}{'version'};
    if ( !defined $config_version ) {
        $log->error("Package config must provide 'version'");
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

    if ( $config_version ne $package_version ) {
        $log->error(
            "Mismatch package versions ($package_version / $config_version)");
        return;

    }

    my %package_details = (
        %{ $config->{'Package'} },
        'prereqs'    => $config->{'Prereqs'}    || {},
        'build_opts' => $config->{'build_opts'} || {},
    );

    return %package_details;
}

__PACKAGE__->meta->make_immutable;

no Moose;

1;

__END__

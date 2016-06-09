package Pakket::Builder;
# ABSTRACT: Build pakket packages

use Moose;
use JSON;
use Path::Tiny                qw< path        >;
use File::Find                qw< find        >;
use File::Copy::Recursive     qw< dircopy     >;
use File::Basename            qw< basename dirname >;
use Algorithm::Diff::Callback qw< diff_hashes >;
use Types::Path::Tiny         qw< Path >;
use TOML::Parser;

use Pakket::Log;
use Pakket::Bundler;
use Pakket::ConfigReader;

use constant {
    ALL_PACKAGES_KEY => '',
};

with 'Pakket::Role::RunCommand';

has config_dir => (
    is      => 'ro',
    isa     => Path,
    default => sub { Path::Tiny->cwd },
);

has source_dir => (
    is      => 'ro',
    isa     => Path,
    default => sub { Path::Tiny->cwd },
);

has build_dir => (
    is      => 'ro',
    isa     => Path,
    lazy    => 1,
    default => sub { Path::Tiny->tempdir('BUILD-XXXXXX', CLEANUP => 0 ) },
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
    is      => 'ro',
    isa     => Path,
    coerce  => 1,
    default => sub {'pkg_index.json'},
);

has index => (
    is      => 'ro',
    isa     => 'HashRef',
    lazy    => 1,
    default => sub { decode_json( path( $_[0]->index_file )->slurp_utf8 ) },
);

has bundler => (
    is      => 'ro',
    isa     => 'Pakket::Bundler',
    lazy    => 1,
    builder => '_build_bundler',
);

has bundler_args => (
    is        => 'ro',
    isa       => 'HashRef',
    default   => sub { +{} },
);

sub _build_bundler {
    my $self = shift;
    Pakket::Bundler->new( $self->bundler_args );
}

sub build {
    my ( $self, $category, $package ) = @_;
    $self->_setup_build_dir;
    $self->run_build( $category, $package );
}

sub DEMOLISH {
    my $self      = shift;
    my $build_dir = $self->build_dir;

    if ( ! $self->keep_build_dir ) {
        log_info { "Removing build dir $build_dir" }

        # "safe" is false because it might hit files which it does not have
        # proper permissions to delete (example: ZMQ::Constants.3pm)
        # which means it won't be able to remove the directory
        path($build_dir)->remove_tree( { safe => 0 } );
    }
}

sub _setup_build_dir {
    my $self = shift;

    log_info { 'Creating build dir ' . $self->build_dir };
    my $prefix_dir = path( $self->build_dir, 'main' );

    -d $prefix_dir or $prefix_dir->mkpath;
}

sub get_latest_version {
    my ( $self, $category, $package ) = @_;
    return $self->index->{$category}{$package}{'latest'};
}

sub run_build {
    my ( $self, $category, $package_name, $package_args ) = @_;

    my $full_package_name = "$category/$package_name";

    # FIXME: this should be cleaned up as a proper excludes list
    $full_package_name eq 'perl/perl' and return;

    if ( $self->is_built->{$full_package_name}++ ) {
        log_info { "We already built $full_package_name, skipping..." };
        return;
    }

    log_notice { "Working on $full_package_name" };

    $package_args ||= {};
    my $package_version = $package_args->{'version'}
        // $self->get_latest_version( $category, $package_name );

    $package_version
        or log_fatal { $_[0] }
        "Could not find a version number for a package ($package_version)";

    # FIXME: the config class should have "mandatory" fields, add checks

    # read the configuration
    my $config_file = path( $self->config_dir, $category, $package_name,
        "$package_version.toml" );

    -r $config_file
        or exit log_critical { $_[0] }
                "Could not find package information ($config_file)";

    my $config_reader = Pakket::ConfigReader->new(
        'type' => 'TOML',
        'args' => [ filename => $config_file ],
    );

    my $config = $config_reader->read_config;

    # double check we have the right package configuration
    my $config_name = $config->{'Package'}{'name'}
        or exit log_critical { $_[0] }
                q{Package config must provide 'name'};

    my $config_category = $config->{'Package'}{'category'}
        or exit log_critical { $_[0] }
                q{Package config must provide 'category'};

    $config_name eq $package_name
        or exit log_critical { $_[0] }
                "Mismatch package names ($package_name / $config_name)";

    $config_category eq $category
        or exit log_critical { $_[0] }
                "Mismatch package categories "
              . "($category / $config_category)";

    # recursively build prereqs
    # starting with system libraries
    # FIXME: we're currently not using the third parameter

    if ( my $system_prereqs = $config->{'Prereqs'}{'system'} ) {
        foreach my $prereq_category (qw<configure runtime>) {
            foreach
                my $prereq ( keys %{ $system_prereqs->{$prereq_category} } )
            {
                $self->run_build( 'system', $prereq,
                    $system_prereqs->{$prereq_category}{$prereq} );
            }
        }
    }

    if ( my $perl_prereqs = $config->{'Prereqs'}{'perl'} ) {
        foreach my $prereq_category (qw<configure runtime>) {
            foreach my $prereq ( keys %{ $perl_prereqs->{$prereq_category} } )
            {
                $self->run_build( 'perl', $prereq,
                    $perl_prereqs->{$prereq_category}{$prereq} );
            }
        }
    }

    my $package_src_dir = path(
        $self->source_dir,
        $self->index->{$category}{$package_name}{'versions'}{$package_version},
    );

    log_info { 'Copying package files' };
    -d $package_src_dir
        or exit log_critical { $_[0] }
                "Cannot find source dir: $package_src_dir";

    my $top_build_dir = $self->build_dir;

    # FIXME: we shouldn't be generating PKG_CONFIG_PATH every time
    my $pkgconfig_path = path( $top_build_dir, qw<main lib pkgconfig> );
    log_info { "Setting PKG_CONFIG_PATH=$pkgconfig_path" };
    local $ENV{'PKG_CONFIG_PATH'} = $pkgconfig_path;

    my $main_build_dir = path( $top_build_dir, 'main' );
    log_info { "Setting LD_LIBRARY_PATH=$main_build_dir" };
    local $ENV{'LD_LIBRARY_PATH'} = $main_build_dir;

    # FIXME: Remove in favor of a ::Build::System, ::Build::Perl, etc.
    # FIXME: $package_dst_dir is dictated from the category
    if ( $config_category eq 'system' ) {
        my $package_dst_dir = path(
            $top_build_dir,
            'src',
            $category,
            basename($package_src_dir),
        );

        dircopy( $package_src_dir, $package_dst_dir );

        $self->build_package(
            $package_name,    # zeromq
            $package_dst_dir, # /tmp/BUILD-1/src/system/zeromq-1.4.1
            $main_build_dir,  # /tmp/BUILD-1/main
        );
    } elsif ( $config_category eq 'perl' ) {
        my $package_dst_dir = path(
            $top_build_dir,
            'src',
            $category,
            basename($package_src_dir),
        );

        dircopy( $package_src_dir, $package_dst_dir );

        $self->build_perl_package(
            $package_name,    # ZMQ::Constants
            $package_dst_dir, # /tmp/BUILD-1/src/perl/ZMQ-Constants-...
            $main_build_dir,  # /tmp/BUILD-1/main
        );
    } else {
        exit log_critical { $_[0] }
             "Unrecognized category ($config_category), cannot build this.";
    }

    $self->is_built->{$full_package_name} = 1;

    log_info { 'Scanning directory.' };
    # XXX: this is just a bit of a smarter && dumber rsync(1):
    # rsync -qaz BUILD/main/ output_dir/
    # the reason is that we need the diff.
    # if you can make it happen with rsync, remove all of this. :P
    # perhaps rsync(1) should be used to deploy the package files
    # (because then we want *all* content)
    # (only if unpacking it directly into the directory fails)
    my $package_files = $self->retrieve_new_files(
        $category, $package_name, $main_build_dir
    );

    keys %{$package_files}
        or exit log_critical { $_[0] }
                'This is odd. Build did not generate new files. '
              . 'Cannot package. Stopping.';

    log_info { "Bundling $full_package_name" };
    $self->bundler->bundle(
        $main_build_dir,
        {
            category => $category,
            name     => $package_name,
            version  => $config->{'Package'}{'version'},
            config   => $config,
        },
        $package_files,
    );

    # store per all packages to get the diff
    @{ $self->build_files_manifest }{ keys %{$package_files} } =
        values %{$package_files};
}

sub retrieve_new_files {
    my ( $self, $category, $package_name, $build_dir ) = @_;

    my $nodes     = $self->scan_directory($build_dir);
    my $new_files = $self->_diff_nodes_list(
        $self->build_files_manifest,
        $nodes,
    );

    return $new_files;
}

sub scan_directory {
    my ( $self, $dir ) = @_;
    my $nodes = {};

    File::Find::find( sub {
        # $File::Find::dir  = '/some/path'
        # $_                = 'foo.ext'
        # $File::Find::name = '/some/path/foo.ext'
        my $filename = $File::Find::name;

        # skip directories, we only want files
        -f $filename or return;

        # save the symlink path in order to symlink them
        if ( -l $filename ) {
            path( $nodes->{$filename} = readlink $filename )->is_absolute
                and exit log_critical { $_[0] }
                         'Error. '
                       . 'Absolute path symlinks aren\'t supported.';
        } else {
            $nodes->{$filename} = '';
        }
    }, $dir );

    return $nodes;
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
            exit log_critical { $_[0] }
                 "Last build deleted previously existing file: $_[0]";
        },
    );

    return \%nodes_diff;
}

sub build_package {
    my ( $self, $package, $build_dir, $prefix ) = @_;

    log_info { "Building $package" };

    $self->run_command(
        $build_dir,
        [ './configure', "--prefix=$prefix" ],
    );

    $self->run_command( $build_dir, ['make'] );

    $self->run_command( $build_dir, ['make', 'install'] );

    log_info { "Done preparing $package" };
}

sub build_perl_package {
    my ( $self, $package, $build_dir, $prefix ) = @_;

    log_info { "Building Perl module: $package" };

    my $opts = {
        env => {
            PERL5LIB => path( $prefix, qw<lib perl5> )->stringify
                . ":$ENV{PERL5LIB}",
        },
    };

    my $original_dir = Path::Tiny->cwd;

    $self->run_command(
        $build_dir,
        [ "$^X", 'Makefile.PL', "INSTALL_BASE=$prefix" ],
        $opts,
    );

    $self->run_command( $build_dir, ['make'], $opts );

    $self->run_command( $build_dir, ['make', 'install'], $opts );

    log_info { "Done preparing $package" };
}

__PACKAGE__->meta->make_immutable;

1;

__END__

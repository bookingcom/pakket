package Pakket::CLI::Command::build;
# ABSTRACT: Build a Pakket package

use strict;
use warnings;

use Path::Tiny      qw< path >;
use Log::Any::Adapter;

use Pakket::Constants qw< PAKKET_PACKAGE_SPEC >;
use Pakket::CLI '-command';
use Pakket::Builder;
use Pakket::Log;
use Pakket::Repo qw< all_packages_in_index_file >;

# TODO:
# - move all hardcoded values (confs) to constants
# - add make process log (and add it with -v -v)
# - check all operations (chdir, mkpath, etc.) (move() already checked)
# - should we detect a file change during BUILD and die/warn?
# - stop calling system(), use a proper Open module instead so we can
#   easily check the success/fail and protect against possible injects

# FIXME: pass on the "output-dir" to the bundler

# FIXME: turn this module into a proper class, don't use global variables
my $repo;

sub abstract    { 'Build a package' }
sub description { 'Build a package' }

sub opt_spec {
    return (
        [ 'index-file=s',   'path to pkg_index.json', { 'required' => 1 } ],
        [ 'from-index',     'build everything from the index' ],
        [ 'category=s',     'build only this key the index' ],
        [ 'input-file=s',   'build stuff from this file' ],
        [ 'input-json=s',   'build stuff from this json file' ],
	[ 'skip=s',         'skip this index entry' ],
        [ 'build-dir=s',    'use an existing build directory' ],
        [ 'keep-build-dir', 'do not delete the build directory' ],
        [
            'config-dir=s',
            'directory holding the configurations',
            { 'required' => 1 }
        ],
        [
            'source-dir=s',
            'directory holding the sources',
            { 'required' => 1 }
        ],
        [ 'output-dir=s', 'output directory (default: .)' ],
        [ 'verbose|v+',   'verbose output (can be provided multiple times)' ],
    );
}

sub validate_args {
    my ( $self, $opt, $args ) = @_;

    my $config_dir = path( $opt->{'config_dir'} );
    $config_dir->exists && $config_dir->is_dir
        or $self->usage_error("Incorrect config directory specified: '$config_dir'");
    $self->{'builder'}{'config_dir'} = $config_dir;

    my $index_file = path( $opt->{'index_file'} );
    $index_file->exists && $index_file->is_file
        or $self->usage_error("Incorrect index file specified: '$index_file'");
    $self->{'builder'}{'index_file'} = $index_file;

    $repo = Pakket::Repo->new('config_dir' => $config_dir,
                              'index_file' => $index_file);

    if ( defined ( my $output_dir = $opt->{'output_dir'} ) ) {
        $self->{'bundler'}{'bundle_dir'} = path($output_dir)->absolute;
    }

    my @specs;
    if ( defined ( my $file = $opt->{'input_file'} ) ) {
        my $path = path($file);
        $path->exists && $path->is_file
            or $self->usage_error("Bad input file: $path");

        push @specs, $path->lines_utf8( { chomp => 1 } );
    } elsif ( $opt->{'from_index'} ) {
        push @specs, _filter_packages(
            @{$opt}{qw< category skip >},
            @{ $repo->packages_in_index },
        );
    } elsif ( defined ( my $json_file = $opt->{'input_json'} ) ) {
        my $path = path($json_file);
        $path->exists && $path->is_file
            or $self->usage_error("Bad '--input-json' file: $path");

        push @specs, _filter_packages(
            @{$opt}{qw< category skip >},
            @{ $repo->packages_in_index },
        );
    } elsif ( @{$args} ) {
        @specs = @{$args};
    } else {
        $self->usage_error('Must specify at least one package or a file');
    }

    foreach my $spec_str (@specs) {
        my ( $cat, $name, $version ) = $spec_str =~ PAKKET_PACKAGE_SPEC()
            or $self->usage_error("Provide category/name, not '$spec_str'");

        # Latest version is default
        if ( !defined $version && defined $repo ) {
            $version = $repo->latest_version_for($cat, $name);
        }

        push @{ $self->{'to_build'} }, +{
            'category' => $cat,
            'name'     => $name,
            'version'  => $version,
        };
    }

    if ( $opt->{'build_dir'} ) {
        -d $opt->{'build_dir'}
            or die "You asked to use a build dir that does not exist.\n";

        $self->{'builder'}{'build_dir'} = $opt->{'build_dir'};
    }

    $self->{'builder'}{'keep_build_dir'} = $opt->{'keep_build_dir'};

    Log::Any::Adapter->set( 'Dispatch',
        'dispatcher' => Pakket::Log->build_logger( $opt->{'verbose'} ) );

    foreach my $opt_name ( qw<config_dir source_dir> ) {
        $opt->{$opt_name}
            and $self->{'builder'}{$opt_name} = path( $opt->{$opt_name} );
    }
}

sub execute {
    my $self    = shift;
    my $builder = Pakket::Builder->new(
        # default main object
        map( +(
            defined $self->{'builder'}{$_}
                ? ( $_ => $self->{'builder'}{$_} )
                : ()
        ), qw< config_dir source_dir build_dir keep_build_dir index_file > ),

        # bundler args
        'bundler_args' => {
            map( +(
                defined $self->{'bundler'}{$_}
                    ? ( $_ => $self->{'bundler'}{$_} )
                    : ()
            ), qw< bundle_dir > ),
        },
    );

    foreach my $prereq_hashref ( @{ $self->{'to_build'} } ) {
        $builder->build( %{$prereq_hashref} );
    }
}

sub _filter_packages {
    my ( $cat, $skip, @packages ) = @_;

    $cat || $skip
        or return @packages;

    my @filtered_pkgs;
    my @skips = split /,/xms, $skip;

    foreach my $pkg_str ( @{ $repo->packages_in_index } ) {
        # if category, skip not in category
        if ($cat) {
            $pkg_str =~ m{^$cat/}xms
                or next;
        }

        # if skip pairs, skip them
        foreach my $skip_pair (@skips) {
            $pkg_str =~ /^\Q$skip_pair\E/xms
                and next;
        }

        # add whatever is left
        push @filtered_pkgs, $pkg_str;
    }

    return @filtered_pkgs;
}

1;

__END__

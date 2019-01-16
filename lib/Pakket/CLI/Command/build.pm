package Pakket::CLI::Command::build;
# ABSTRACT: Build a Pakket parcel

use strict;
use warnings;

use Pakket::CLI '-command';
use Pakket::Constants qw< PAKKET_PACKAGE_SPEC >;
use Pakket::Config;
use Pakket::Builder;
use Pakket::PackageQuery;
use Pakket::Log;
use Pakket::Utils::Repository qw< gen_repo_config >;

use Path::Tiny qw< path >;
use Log::Any   qw< $log >;
use Log::Any::Adapter;

sub abstract    { 'Build a package' }
sub description { 'Build a package' }

sub opt_spec {
    return (
        [ 'input-file=s',    'build stuff from this file' ],
        [ 'build-dir=s',     'use an existing build directory' ],
        [ 'keep-build-dir',  'do not delete the build directory' ],
        [ 'spec-dir=s',      'directory holding the specs' ],
        [ 'source-dir=s',    'directory holding the sources' ],
        [ 'output-dir=s',    'output directory (default: .)' ],
        [ 'config|c=s',      'configuration file' ],
        [ 'verbose|v+',      'verbose output (can be provided multiple times)' ],
        [ 'log-file=s',      'Log file (default: build.log)' ],
        [ 'ignore-failures', 'Continue even if some builds fail' ],
        [ 'overwrite',       'overwrite artifacts even if they are already exist' ],
    );
}

sub _determine_config {
    my ( $self, $opt ) = @_;

    my $config_file = $opt->{'config'};
    my $config_reader = Pakket::Config->new(
        $config_file ? ( 'files' => [$config_file] ) : (),
    );

    my $config = $config_reader->read_config;

    # Setup default repos
    my %repo_opt = (
        'spec'   => 'spec_dir',
        'source' => 'source_dir',
        'parcel' => 'output_dir',
    );

    foreach my $type ( keys %repo_opt ) {
        my $opt_key   = $repo_opt{$type};
        my $directory = $opt->{$opt_key};
        if ( $directory ) {
            my $repo_conf = $self->gen_repo_config( $type, $directory );
            $config->{'repositories'}{$type} = $repo_conf;
        }
        $config->{'repositories'}{$type}
            or $self->usage_error("Missing configuration for $type repository");
    }

    return $config;
}

sub validate_args {
    my ( $self, $opt, $args ) = @_;

    $opt->{'config'} = $self->_determine_config($opt);
    $opt->{'config'}{'env'}{'cli'} = 1;

    my $log_file = $opt->{'log_file'} || $opt->{'config'}{'log_file'};
    Log::Any::Adapter->set(
        'Dispatch',
        'dispatcher' => Pakket::Log->build_logger(
            $opt->{'verbose'}, $log_file,
        ),
    );

    my @specs;
    if ( defined ( my $file = $opt->{'input_file'} ) ) {
        my $path = path($file);
        $path->exists && $path->is_file
            or $self->usage_error("Bad input file: $path");

        push @specs, $path->lines_utf8( { 'chomp' => 1 } );
    } elsif ( @{$args} ) {
        @specs = @{$args};
    } else {
        $self->usage_error('Must specify at least one package or a file');
    }

    foreach my $spec_str (@specs) {
        my ( $cat, $name, $version, $release ) =
            $spec_str =~ PAKKET_PACKAGE_SPEC();

        $cat && $name && $version && $release
            or $self->usage_error(
                "Provide category/name=version:release, not '$spec_str'",
            );

        my $query;
        eval { $query = Pakket::PackageQuery->new_from_string($spec_str); 1; }
        or do {
            my $error = $@ || 'Zombie error';
            $log->debug("Failed to create PackageQuery: $error");
            $self->usage_error(
                "We do not understand this package string: $spec_str",
            );
        };

        push @{ $self->{'queries'} }, $query;
    }

    if ( $opt->{'build_dir'} ) {
        path( $opt->{'build_dir'} )->is_dir
            or die "You asked to use a build dir that does not exist.\n";
    }
}

sub execute {
    my ( $self, $opt ) = @_;

    my $builder = Pakket::Builder->new(
        'config'    => $opt->{'config'},
        'overwrite' => $opt->{overwrite} ? {name => $self->{queries}[0]{name}} : +{},

        # Maybe we have it, maybe we don't
        map( +(
            defined $opt->{$_}
                ? ( $_ => $opt->{$_} )
                : ()
        ), qw< build_dir keep_build_dir > ),
    );

    if ( ! $opt->{'ignore_failures'} ) {
        $builder->build( @{ $self->{'queries'} } );
        return;
    }

    foreach my $query ( @{ $self->{'queries'} } ) {
        eval {
            $builder->build($query);
            1;
        } or do {
            my $error = $@ || 'Zombie error';
            $log->warnf('Failed to build %s, skipping.', $query->full_name );
        };
    }

    return;
}

1;

__END__

=pod

=head1 SYNOPSIS

    $ pakket build perl/Dancer2

    $ pakket build native/tidyp=1.04

    $ pakket build --help

        --input-file STR     build stuff from this file
        --build-dir STR      use an existing build directory
        --keep-build-dir     do not delete the build directory
        --spec-dir STR       directory holding the specs
        --source-dir STR     directory holding the sources
        --output-dir STR     output directory (default: .)
        -c STR --config STR  configuration file
        -v --verbose         verbose output (can be provided multiple times)
        --log-file STR       Log file (default: build.log)
        --ignore-failures    Continue even if one the builds failed

=head1 DESCRIPTION

Once you have your configurations (spec) and the sources for your
packages, you can issue a build of them using this command. It will
generate parcels, which are the build artifacts.

(The parcels are equivalent of C<.rpm> or C<.deb> files.)

    # Build latest version of package "Dancer2" of category "perl"
    $ pakket build perl/Dancer2

    # Build specific version
    $ pakket build perl/Dancer2=0.205000

Depending on the configuration you have for Pakket, the result will
either be saved in a file or in a database or sent to a remote server.

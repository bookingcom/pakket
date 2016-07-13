package Pakket::CLI::Command::build;
# ABSTRACT: The pakket build command

use strict;
use warnings;
use Pakket::CLI '-command';
use Pakket::Builder;
use Pakket::Log;
use Path::Tiny      qw< path >;
use Log::Any::Adapter;

use constant {
    INDEX_CATEGORY     => 0,
    INDEX_PACKAGE_NAME => 1,
    INDEX_PARAMETERS   => 2,
};

# TODO:
# - move all hardcoded values (confs) to constants
# - add make process log (and add it with -v -v)
# - check all operations (chdir, mkpath, etc.) (move() already checked)
# - should we detect a file change during BUILD and die/warn?
# - stop calling system(), use a proper Open module instead so we can
#   easily check the success/fail and protect against possible injects

# FIXME: pass on the "output-dir" to the bundler

sub abstract    { 'Build a package' }
sub description { 'Build a package' }

sub opt_spec {
    return (
        [ 'index-file=s',   'path to pkg_index.json'                          ],
        [ 'input-file=s',   'build stuff from this file'                      ],
        [ 'build-dir=s',    'use an existing build directory'                 ],
        [ 'keep-build-dir', 'do not delete the build directory'               ],
        [ 'config-dir=s',   'directory holding the configurations'            ],
        [ 'source-dir=s',   'directory holding the sources'                   ],
        [ 'output-dir=s',   'output directory (default: .)'                   ],
        [ 'verbose|v+',     'verbose output (can be provided multiple times)' ],
    );
}

sub validate_args {
    my ( $self, $opt, $args ) = @_;

    if ( defined ( my $output_dir = $opt->{'output_dir'} ) ) {
        $self->{'bundler'}{'bundle_dir'} = path($output_dir)->absolute;
    }

    my @packages;
    if ( my $file = $opt->{'input_file'} ) {
        my $path = path($file);
        $path->exists && $path->is_file
            or $self->usage_error("Bad file: $path");

        push @packages, $path->lines_utf8( { chomp => 1 } );
    } elsif ( @{$args} ) {
        @packages = @{$args};
    } else {
        $self->usage_error('Must specify at least one package or a file');
    }

    if ( my $file = $opt->{'index_file'} ) {
        my $path = path($file);
        $path->exists && $path->is_file
            or $self->usage_error('Incorrect index file specified');

        $self->{'builder'}{'index_file'} = $path;
    }

    foreach my $package_name (@packages) {
        my ( $cat, $package, $version ) = split m{/}ms, $package_name;

        $cat && $package
            or $self->usage_error('Wrong category/package provided.');

        push @{ $self->{'to_build'} }, [ $cat, $package, $version ];
    }

    if ( $opt->{'build_dir'} ) {
        -d $opt->{'build_dir'}
            or die "You asked to use a build dir that does not exist.\n";

        $self->{'builder'}{'build_dir'} = $opt->{'build_dir'};
    }

    $self->{'builder'}{'keep_build_dir'} = $opt->{'keep_build_dir'};
    $self->{'builder'}{'verbose'}        = $opt->{'verbose'};

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
        bundler_args => {
            map( +(
                defined $self->{'bundler'}{$_}
                    ? ( $_ => $self->{'bundler'}{$_} )
                    : ()
            ), qw< bundle_dir > ),
        },
    );

    my $verbose = $self->{'builder'}{'verbose'};
    my $logger  = Pakket::Log->build_logger($verbose);
    Log::Any::Adapter->set( 'Dispatch', dispatcher => $logger );

    foreach my $tuple ( @{ $self->{'to_build'} } ) {
        $builder->build(
            $tuple->[ +INDEX_CATEGORY ],
            $tuple->[ +INDEX_PACKAGE_NAME ],

            defined $tuple->[ +INDEX_PARAMETERS ]
                ? { version => $tuple->[ +INDEX_PARAMETERS ] }
                : (),
        );
    }
}

1;

__END__

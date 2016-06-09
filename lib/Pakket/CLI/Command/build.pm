package Pakket::CLI::Command::build;
# ABSTRACT: The pakket build command

use strict;
use warnings;
use Pakket::CLI -command;
use Pakket::Builder;
use Pakket::Log;
use Path::Tiny      qw< path >;
use Log::Contextual qw< set_logger >;

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
        [ 'category=s',     'pakket category ("perl", "system", etc.)'        ],
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

    $self->{'category'} = $opt->{'category'};

    if ( defined ( my $output_dir = $opt->{'output_dir'} ) ) {
        $self->{'bundler'}{'bundle_dir'} = path($output_dir)->absolute;
    }

    $args->[0]
        or $self->usage_error('Must specify package');

    my ( $cat, $package ) = split '/', $args->[0];

    # did we get a full path spec (category/package)
    if ($package) {
        # if there is a category, it *has* to match
        # the category provided by the full spec
        $self->{'category'} && $self->{'category'} ne $cat
            and $self->usage_error(
                sprintf "You specified two categories: '%s' and '%s'\n",
                        $self->{'category'},
                        $cat
            );

        # use the category we got from the full spec if we don't
        # have one defined already
        # (and if we do, they will match anyway - see check above)
        $self->{'category'} //= $cat;
    }

    # if there is no package, the first item (now in $cat)
    # is the package name
    $self->{'package'} = $package || $cat;

    $self->{'category'}
        or $self->usage_error('You must provide a category');

    $self->{'category'}
        or $self->usage_error('I don\'t have a category for this package.');

    if ( $opt->{'build_dir'} ) {
        -d $opt->{'build_dir'}
            or die "You asked to use a build dir that does not exist.\n";

        $self->{'builder'}{'build_dir'} = path( $opt->{'build_dir'} );
    }

    $self->{'builder'}{'keep_build_dir'} = $opt->{'keep_build_dir'};
    $self->{'builder'}{'config_dir'}     = path( $opt->{'config_dir'} );
    $self->{'builder'}{'source_dir'}     = path( $opt->{'source_dir'} );
    $self->{'builder'}{'verbose'}        = $opt->{'verbose'};
}

sub execute {
    my $self    = shift;
    my $builder = Pakket::Builder->new(
        # default main object
        map( +(
            defined $self->{'builder'}{$_}
                ? ( $_ => $self->{'builder'}{$_} )
                : ()
        ), qw< config_dir source_dir build_dir keep_build_dir > ),

        # bundler args
        bundler_args => {
            map( +(
                defined $self->{'bundler'}{$_}
                    ? ( $_ => $self->{'bundler'}{$_} )
                    : ()
            ), qw< bundle_dir > )
        },
    );

    my $verbose = $self->{'builder'}{'verbose'};
    my $logger  = Pakket::Log->build_logger($verbose);
    set_logger $logger;

    $builder->build( $self->{'category'}, $self->{'package'} );
}

1;

__END__

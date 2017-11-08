package Pakket::CLI::Command::manage;
# ABSTRACT: The pakket manage command

use strict;
use warnings;

use Path::Tiny qw< path  >;
use Ref::Util  qw< is_arrayref is_coderef >;
use Log::Any   qw< $log >; # to log
use Log::Any::Adapter;     # to set the logger

use Pakket::CLI '-command';
use Pakket::Log;
use Pakket::Config;
use Pakket::Manager;
use Pakket::PackageQuery;
use Pakket::Requirement;
use Pakket::Utils::Repository qw< gen_repo_config >;
use Pakket::Constants qw<
    PAKKET_PACKAGE_SPEC
    PAKKET_VALID_PHASES
>;

sub abstract    { 'Manage Pakket packages and repositories' }
sub description { return <<'_END_DESC';
This command manages Pakket packages across repositories.
It allows you to add new specs, sources, and packages, as well
as edit existing ones, and view your repositories.
_END_DESC
}

my %commands = map +( $_ => 1 ), qw<
    add-package
    remove-package
    list-package
    remove-parcel
    add-deps
    list-deps
    list-specs
    list-sources
    list-parcels
>;

my %command_aliases = (
    'add'           => 'add-package',
    'remove'        => 'remove-package',
    'remove_parcel' => 'remove-parcel',
    'show'          => 'list-package',
    'show-deps'     => 'list-deps',

    'deps'          => sub {
        # This can be either add-deps or deps-remove
        my $self = shift;
        my $opt  = $self->{'opt'};

        $opt->{'add'} || $opt->{'remove'}
            or $self->usage_error( "Missing arg: add/remove (mandatory for 'deps')" );

        foreach my $type ( qw< add remove > ) {
            if ( $opt->{$type} ) {
                scalar keys %{ $opt->{$type} } > 1
                    and $self->usage_error("Cannot provide multiple --$type");

                my $phase = ( keys %{ $opt->{$type} } )[0];

                $opt->{'phase'} = $phase;
                $opt->{'on'}    = $opt->{$type}{$phase};

                delete $opt->{$type};

                return "$type-deps";
            }
        }

        $self->usage_error("Invalid old deps command: deps");
    },

    'list'          => sub {
        # This can be either list-spec, list-source, or list-parcel
        my $self = shift;
        my $args = $self->{'args'};

        $args && @{$args}
            or $self->usage_error('Not enough arguments for list');

        if ( $args->[0] eq 'parcels' ) {
            shift @{$args};
            return 'list-parcels';
        } elsif ( $args->[0] eq 'specs' ) {
            shift @{$args};
            return 'list-specs';
        } elsif ( $args->[0] eq 'sources' ) {
            shift @{$args};
            return 'list-sources';
        }

        $self->usage_error("Invalid old deps command: list $args->[0]");
    },
);


sub opt_spec {
    return (
        [ 'cpanfile=s',   'cpanfile to configure from' ],
        [ 'spec-dir=s',   'directory to write the spec to (JSON files)' ],
        [ 'source-dir=s', 'directory to write the sources to (downloads if provided)' ],
        [ 'parcel-dir=s', 'directory where build output (parcels) are' ],
        [ 'cache-dir=s',  'directory to get sources from (optional)' ],
        [ 'additional-phase=s@',
          "additional phases to use ('develop' = author_requires, 'test' = test_requires). configure & runtime are done by default.",
        ],
        [ 'config|c=s',   'configuration file' ],
        [ 'verbose|v+',   'verbose output (can be provided multiple times)' ],
        [ 'phase=s',      '(deps) What phase is the dependency' ],
        [ 'on=s',         '(deps) What is the dependency on'    ],
        [ 'cpan-02packages=s', '02packages file (optional)'     ],
        [ 'no-deps',      'do not add dependencies (top-level only)' ],
        [ 'is-local=s@',  'do not use upstream sources (i.e. CPAN) for given packages' ],
        [ 'requires-only', 'do not set recommended/suggested dependencies' ],
        [ 'no-bootstrap',  'skip bootstrapping phase (toolchain packages)' ],
        [ 'source-archive=s', 'archve with sources (optional, only for native)' ],
        [ 'add=s%',       '[DEPRECATED] (deps) add the following dependency (phase=category/name=version[:release])' ],
        [ 'remove=s%',    '[DEPRECATED] (deps) remove the following dependency (phase=category/name=version[:release])' ],
    );
}

sub validate_args {
    my ( $self, $opt, $args ) = @_;

    Log::Any::Adapter->set(
        'Dispatch',
        'dispatcher' => Pakket::Log->build_logger( $opt->{'verbose'} ),
    );

    $self->{'opt'}  = $opt;
    $self->{'args'} = $args;

    $self->_validate_arg_command;
    $self->_validate_arg_cache_dir;
    $self->_read_config;
}

sub execute {
    my $self = shift;

    my $command = $self->{'command'};

    my $is_local = +{
        map { $_ => 1 } @{ $self->{'opt'}{'is_local'} }
    };

    my $manager = Pakket::Manager->new(
        config          => $self->{'config'},
        cpanfile        => $self->{'cpanfile'},
        cache_dir       => $self->{'cache_dir'},
        phases          => $self->{'gen_phases'},
        package         => $self->{'spec'},
        file_02packages => $self->{'file_02packages'},
        no_deps         => $self->{'opt'}{'no_deps'},
        requires_only   => $self->{'opt'}{'requires_only'},
        no_bootstrap    => $self->{'opt'}{'no_bootstrap'},
        is_local        => $is_local,
        source_archive  => $self->{'source_archive'},
    );

    if ( $command eq 'add-package' ) {
        $manager->add_package;

    } elsif ( $command eq 'remove-package' ) {
        # TODO: check we are allowed to remove package (dependencies)
        $manager->remove_package('spec');
        $manager->remove_package('source');

    } elsif ( $command eq 'remove-parcel' ) {
        # TODO: check we are allowed to remove package (dependencies)
        $manager->remove_package('parcel');

    } elsif ( $command eq 'add-deps' ) {
        $manager->add_dependency( $self->{'dependency'} );
    } elsif ( $command eq 'remove-deps' ) {
        $manager->remove_dependency( $self->{'dependency'} );

    } elsif ( $command =~ m{^ list- (spec | source | parcel) s $}xms ) {
        # list-parcel list-spec list-source
        $manager->list_ids( $self->{'list_type'} );
    } elsif ( $command eq 'list-package' ) {
        $manager->show_package_config;

    } elsif ( $command eq 'list-deps' ) {
        $manager->show_package_deps;
    }
}

sub _read_config {
    my $self = shift;

    my $config_file   = $self->{'opt'}{'config'};
    my $config_reader = Pakket::Config->new(
        $config_file ? ( 'files' => [$config_file] ) : (),
    );

    $self->{'config'} = $config_reader->read_config;

    $self->_validate_repos;
}

sub _validate_repos {
    my $self = shift;

    my %cmd2repo = (
        'add-package'    => [ 'spec', 'source' ],
        'remove-package' => [ 'spec', 'source' ],
        'remove-parcel'  => [ 'parcel' ],
        'list-package'   => [ 'spec'   ],
        'add-deps'       => [ 'spec'   ],
        'remove-deps'    => [ 'spec'   ],
        'list-deps'      => [ 'spec'   ],
        'list-specs'     => [ 'spec'   ],
        'list-parcels'   => [ 'parcel' ],
        'list-sources'   => [ 'source' ],
    );

    my $config  = $self->{'config'};
    my $command = $self->{'command'};

    my @required_repos = @{ $cmd2repo{$command} };

    my %repo_opt = (
        'spec'   => 'spec_dir',
        'source' => 'source_dir',
        'parcel' => 'parcel_dir',
    );

    for my $type ( @required_repos ) {
        my $opt_key   = $repo_opt{$type};
        my $directory = $self->{'opt'}{$opt_key};
        if ( $directory ) {
            my $repo_conf = $self->gen_repo_config( $type, $directory );
            $config->{'repositories'}{$type} = $repo_conf;
        }
        $config->{'repositories'}{$type}
            or $self->usage_error("Missing configuration for $type repository");
    }
}

sub _validate_arg_command {
    my $self     = shift;
    my @cmd_list = keys %commands;

    my $command = shift @{ $self->{'args'} }
        or $self->usage_error( "Must pick action (@{[ join '/', @cmd_list ]})" );

    if ( my $alias = $command_aliases{$command} ) {
        $command = is_coderef($alias) ? $alias->($self) : $alias;
    }

    $commands{$command}
        or $self->usage_error( "Wrong command (@{[ join '/', @cmd_list ]})" );

    $self->{'command'} = $command;

    $command eq 'add-package'    and $self->_validate_args_add;       # FIXME: Rename method
    $command eq 'remove-package' and $self->_validate_args_remove;    # FIXME: Rename method
    $command eq 'remove-parcel'  and $self->_validate_args_remove_parcel;
    $command eq 'list-deps'      and $self->_validate_args_show_deps; # FIXME: Rename method
    $command eq 'list-package'   and $self->_validate_args_show;      # FIXME: Rename method

    $command eq 'add-deps' || $command eq 'remove-deps'
       and $self->_validate_args_dependency;

   # list-parcel list-spec list-source
    $command =~ m{^ (?: list- ( parcel | spec | source ) s ) $}xms
        and $self->{'list_type'} = $1;
}

sub _validate_arg_cache_dir {
    my $self = shift;

    my $cache_dir = $self->{'opt'}{'cache_dir'};

    if ( $cache_dir ) {
        path( $cache_dir )->exists
            or $self->usage_error( "cache-dir: $cache_dir doesn't exist\n" );
        $self->{'cache_dir'} = $cache_dir;
    }
}

sub _validate_args_add {
    my $self = shift;

    my $cpanfile = $self->{'opt'}{'cpanfile'};
    my $additional_phase = $self->{'opt'}{'additional_phase'};

    $self->{'file_02packages'} = $self->{'opt'}{'cpan_02packages'};
    $self->{'source_archive'}  = $self->{'opt'}{'source_archive'};

    if ( $cpanfile ) {
        @{ $self->{'args'} }
            and $self->usage_error( "You can't have both a 'spec' and a 'cpanfile'\n" );
        $self->{'cpanfile'} = $cpanfile;
    } else {
        $self->_read_set_spec_str;
    }

    # TODO: config ???
    $self->{'gen_phases'} = [qw< configure runtime >];
    if ( is_arrayref($additional_phase) ) {
        exists PAKKET_VALID_PHASES->{$_} or $self->usage_error( "Unsupported phase: $_" )
            for @{ $additional_phase };
        push @{ $self->{'gen_phases'} } => @{ $additional_phase };
    }
}

sub _validate_args_remove {
    my $self = shift;
    $self->_read_set_spec_str;
}

sub _validate_args_remove_parcel {
    my $self = shift;
    $self->_read_set_spec_str;
}

sub _validate_args_dependency {
    my $self = shift;
    my $opt  = $self->{'opt'};

    # spec
    $self->_read_set_spec_str;

    # Old: pakket manage deps --add | --remove runtime=Moo perl/Dancer2=...
    # New: pakket manage add-deps perl/Dancer2=... --phase runtime --on perl/Moo=2.000
    defined $opt->{$_} or $self->usage_error("Missing argument $_")
        for qw< phase on >;

    my $dep = $self->_read_spec_str( $opt->{'on'} );

    defined $dep->{'version'}
        or $self->usage_error( "Invalid dependency: missing version" );

    $dep->{'phase'}       = $opt->{'phase'}; # FIXME: Should be in instantiation above
    $self->{'dependency'} = $dep;
}

sub _validate_args_show {
    my $self = shift;
    $self->_read_set_spec_str;
}

sub _validate_args_show_deps {
    my $self = shift;
    $self->_read_set_spec_str;
}

sub _read_spec_str {
    my ( $self, $spec_str ) = @_;

    my $spec;
    if ( $self->{'command'} eq 'add-package' ) {
        my ( $c, $n, $v ) = $spec_str =~ PAKKET_PACKAGE_SPEC();
        !defined $v and $spec = Pakket::Requirement->new( category => $c, name => $n );
    }

    $spec //= Pakket::PackageQuery->new_from_string($spec_str);

    # add supported categories
    if ( !( $spec->category eq 'perl' or $spec->category eq 'native' ) ) {
        $self->usage_error( "Wrong 'name' format\n" );
    }

    return $spec;
}

sub _read_set_spec_str {
    my $self = shift;

    my $spec_str = shift @{ $self->{'args'} };
    $spec_str or $self->usage_error( "Must provide a package id (category/name=version:release)" );

    $self->{'spec'} = $self->_read_spec_str($spec_str);
}

1;

__END__

=pod

=head1 SYNOPSIS

    $ pakket manage add-package perl/Dancer2=0.205000:1
    $ pakket manage list-package perl/Dancer2=0.205000:1
    $ pakket manage remove-package perl/Dancer2=0.205000:1
    $ pakket manage remove-parcel perl/Dancer2=0.205000:1

    $ pakket manage list-deps perl/Dancer2=0.205000:1
    $ pakket manage list-specs
    $ pakket manage list-sources
    $ pakket manage list-parcels

    $ pakket manage [-cv] [long options...]

=head1 DESCRIPTION

The C<manage> command does all management with the repositories. This
includes listing, adding, and removing packages. It includes listing
all information across repositories (specs, sources, parlces), as well
as dependencies for any package.

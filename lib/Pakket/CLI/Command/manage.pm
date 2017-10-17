package Pakket::CLI::Command::manage;
# ABSTRACT: The pakket manage command

use strict;
use warnings;

use Path::Tiny qw< path  >;
use Ref::Util  qw< is_arrayref >;
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

sub abstract    { 'Scaffold a project' }
sub description { 'Scaffold a project' }

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
        [ 'add=s%',       '(deps) add the following dependency (phase=category/name=version[:release])' ],
        [ 'remove=s%',    '(deps) remove the following dependency (phase=category/name=version[:release])' ],
        [ 'cpan-02packages=s', '02packages file (optional)' ],
        [ 'no-deps',      'do not add dependencies (top-level only)' ],
        [ 'is-local=s@',  'do not use upstream sources (i.e. CPAN) for given packages' ],
        [ 'requires-only', 'do not set recommended/suggested dependencies' ],
        [ 'no-bootstrap',  'skip bootstrapping phase (toolchain packages)' ],
        [ 'source-archive=s', 'archve with sources (optional, only for native)' ],
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

    if ( $command eq 'add' ) {
        $manager->add_package;

    } elsif ( $command eq 'remove' ) {
        # TODO: check we are allowed to remove package (dependencies)
        $manager->remove_package('spec');
        $manager->remove_package('source');

    } elsif ( $command eq 'remove_parcel' ) {
        # TODO: check we are allowed to remove package (dependencies)
        $manager->remove_package('parcel');

    } elsif ( $command eq 'deps' ) {
        $self->{'opt'}{'add'}    and $manager->add_dependency( $self->{'dependency'} );
        $self->{'opt'}{'remove'} and $manager->remove_dependency( $self->{'dependency'} );

    } elsif ( $command eq 'list' ) {
        $manager->list_ids( $self->{'list_type'} );

    } elsif ( $command eq 'show' ) {
        $manager->show_package_config;

    } elsif ( $command eq 'show_deps' ) {
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
        'add'           => [ 'spec', 'source' ],
        'remove'        => [ 'spec', 'source' ],
        'remove_parcel' => [ 'parcel' ],
        'deps'          => [ 'spec' ],
        'show'          => [ 'spec' ],
        'show_deps'     => [ 'spec' ],
        'list'          => {
            spec   => [ 'spec'   ],
            parcel => [ 'parcel' ],
            source => [ 'source' ],
        },
    );

    my $config  = $self->{'config'};
    my $command = $self->{'command'};

    my @required_repos = @{
        $command eq 'list'
            ? $cmd2repo{$command}{ $self->{'list_type'} }
            : $cmd2repo{$command}
    };

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
    my $self = shift;

    my $command = shift @{ $self->{'args'} }
        or $self->usage_error("Must pick action (add/remove/remove_parcel/deps/list/show/show_deps)");

    grep { $command eq $_ } qw< add remove remove_parcel deps list show show_deps >
        or $self->usage_error( "Wrong command (add/remove/remove_parcel/deps/list/show/show_deps)" );

    $self->{'command'} = $command;

    $command eq 'add'    and $self->_validate_args_add;
    $command eq 'remove' and $self->_validate_args_remove;
    $command eq 'deps'   and $self->_validate_args_dependency;
    $command eq 'list'   and $self->_validate_args_list;
    $command eq 'show'   and $self->_validate_args_show;
    $command eq 'show_deps'     and $self->_validate_args_show_deps;
    $command eq 'remove_parcel' and $self->_validate_args_remove_parcel;
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

    # dependency
    my $action = $opt->{'add'} || $opt->{'remove'};
    $action or $self->usage_error( "Missing arg: add/remove (mandatory for 'deps')" );

    my ( $phase, $dep_str ) = %{ $action };
    $phase or $self->usage_error( "Invalid dependency: missing phase" );

    my $dep = $self->_read_spec_str($dep_str);
    defined $dep->{'version'}
        or $self->usage_error( "Invalid dependency: missing version" );
    $dep->{'phase'} = $phase;

    $self->{'dependency'}  = $dep;
}

sub _validate_args_list {
    my $self = shift;

    my $type = shift @{ $self->{'args'} };

    $type and grep { $type eq $_ or $type eq $_.'s' } qw< parcel spec source >
        or $self->usage_error( "Invalid type of list (parcels/specs/sources): " . ($type||"") );

    $self->{'list_type'} = $type =~ s/s?$//r;
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
    if ( $self->{'command'} eq 'add' ) {
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

    $ pakket manage add perl/Dancer2=0.205000:1
    $ pakket manage remove perl/Dancer2=0.205000:1
    $ pakket manage remove_parcel perl/Dancer2=0.205000:1
    $ pakket manage deps
    $ pakket manage show
    $ pakket manage list specs
    $ pakket manage list sources
    $ pakket manage list parcels
    $ pakket manage show_deps perl/Dancer2=0.205000:1

    $ pakket manage [-cv] [long options...]

    Scaffold a project
            --cpanfile STR             cpanfile to configure from
            --spec-dir STR             directory to write the spec to (JSON files)
            --source-dir STR           directory to write the sources to
                                       (downloads if provided)
            --parcel-dir STR           directory where build output (parcels) are
            --cache-dir STR            directory to get sources from (optional)
            --additional-phase STR...  additional phases to use ('develop' =
                                       author_requires, 'test' = test_requires).
                                       configure & runtime are done by default.
            -c STR --config STR        configuration file
            -v --verbose               verbose output (can be provided multiple
                                       times)
            --add KEY=STR...           (deps) add the following dependency
                                       (phase=category/name=version[:release])
            --remove KEY=STR...        (deps) remove the following dependency
                                       (phase=category/name=version[:release])
            --cpan-02packages STR      02packages file (optional)
            --no-deps                  do not add dependencies (top-level only)
            --is-local STR...          do not use upstream sources (i.e. CPAN)
                                       for given packages
            --requires-only            do not set recommended/suggested
                                       dependencies
            --no-bootstrap             skip bootstrapping phase (toolchain
                                       packages)

=head1 DESCRIPTION

The C<manage> command does all management with the repositories. This
includes listing, adding, and removing packages. It includes listing
all information across repositories (specs, sources, parlces), as well
as dependencies for any package.

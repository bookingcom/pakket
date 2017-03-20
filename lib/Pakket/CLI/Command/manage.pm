package Pakket::CLI::Command::manage;
# ABSTRACT: The pakket manage command

use strict;
use warnings;

use Path::Tiny qw< path  >;
use List::Util qw< first >;
use Ref::Util  qw< is_arrayref >;
use Log::Any   qw< $log >; # to log
use Log::Any::Adapter;     # to set the logger

use Pakket::CLI '-command';
use Pakket::Log;
use Pakket::Config;
use Pakket::Manager;
use Pakket::Constants qw< PAKKET_VALID_PHASES >;

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
        [ 'remove=s%',    '(deps) add the following dependency (phase=category/name=version[:release])' ],
        [ 'cpan-02packages=s', '02packages file (optional)' ],
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
    my $package;

    my $command = $self->{'command'};

    my $category =
        $self->{'spec'}     ? $self->{'spec'}->category :
        $self->{'cpanfile'} ? 'perl' :
        undef;

    if ( $command =~ /^(?:add|remove|deps|show)$/ and !$self->{'cpanfile'} ) {
        $package = Pakket::Package->new(
            'category' => $category,
            'name'     => $self->{'spec'}->name,
            'version'  => $self->{'spec'}->version,
            'release'  => $self->{'spec'}->release,
        );
    }

    my $manager = Pakket::Manager->new(
        config          => $self->{'config'},
        cpanfile        => $self->{'cpanfile'},
        cache_dir       => $self->{'cache_dir'},
        phases          => $self->{'gen_phases'},
        package         => $package,
        file_02packages => $self->{'file_02packages'},
    );

    if ( $command eq 'add' ) {
        $manager->add_package;

    } elsif ( $command eq 'remove' ) {
        # TODO: check we are allowed to remove package (dependencies)
        $manager->remove_package_spec;
        $manager->remove_package_source;

    } elsif ( $command eq 'deps' ) {
        $self->{'opt'}{'add'}    and $manager->add_dependency( $self->{'dependency'} );
        $self->{'opt'}{'remove'} and $manager->remove_dependency( $self->{'dependency'} );

    } elsif ( $command eq 'list' ) {
        $manager->list_ids( $self->{'list_type'} );

    } elsif ( $command eq 'show' ) {
        $manager->show_package_config;
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
    my $self   = shift;

    my %map = (
        'spec'   => [ 'spec_dir',   'ini'  ],
        'source' => [ 'source_dir', 'spkt' ],
        'parcel' => [ 'parcel_dir', 'pkt'  ],
    );

    my %cmd2repo = (
        'add'    => [ 'spec', 'source' ],
        'remove' => [ 'spec', 'source' ],
        'deps'   => [ 'spec' ],
        'show'   => [ 'spec' ],
        'list'   => {
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

    for my $type ( @required_repos ) {
        my ( $opt_key, $opt_ext ) = @{ $map{$type} };
        my $directory = $self->{'opt'}{$opt_key};

        if ( $directory ) {
            if ( $directory =~ m{^/} ) {
                $config->{'repositories'}{$type} =
                    [
                        'File',
                        'directory'      => $directory,
                        'file_extension' => $opt_ext,
                    ];

                my $path = path($directory);
                $path->exists && $path->is_dir
                    or $self->usage_error("Bad directory for $type repo: $path");

            } elsif ( $directory =~ m{^(https?)://([^/]+)(:[^/]+)?(/.*)?$} ) {
                my ( $protocol, $host, $port, $base_path ) = ( $1, $2, $3, $4 );
                $port or $port = $protocol eq 'http' ? 80 : 443;
                $config->{'repositories'}{$type} =
                    [
                        'HTTP',
                        'host'      => $host,
                        'port'      => $port,
                        'base_path' => $base_path,
                    ];
            }
        }

        $config->{'repositories'}{$type}
            or $self->usage_error("Missing configuration for $type repository");
    }
}

sub _validate_arg_command {
    my $self = shift;

    my $command = shift @{ $self->{'args'} }
        or $self->usage_error("Must pick action (add/remove/deps/list/show)");

    grep { $command eq $_ } qw< add remove deps list show >
        or $self->usage_error( "Wrong command (add/remove/deps/list/show)" );

    $self->{'command'} = $command;

    $command eq 'add'    and $self->_validate_args_add;
    $command eq 'remove' and $self->_validate_args_remove;
    $command eq 'deps'   and $self->_validate_args_dependency;
    $command eq 'list'   and $self->_validate_args_list;
    $command eq 'show'   and $self->_validate_args_show;
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

sub _read_spec_str {
    my ( $self, $spec_str ) = @_;

    my $spec = Pakket::Requirement->new_from_string($spec_str);

    first { $_ eq $spec->category } qw< perl native > # add supported categories
        or $self->usage_error( "Wrong 'name' format\n" );

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

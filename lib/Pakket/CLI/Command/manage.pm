package Pakket::CLI::Command::manage;
# ABSTRACT: The pakket manage command

use strict;
use warnings;

use Path::Tiny qw< path  >;
use List::Util qw< first >;
use Log::Any   qw< $log >; # to log
use Log::Any::Adapter;     # to set the logger

use Pakket::CLI '-command';
use Pakket::Log;
use Pakket::Config;
use Pakket::Scaffolder::Perl;
use Pakket::Constants qw< PAKKET_PACKAGE_SPEC >;

sub abstract    { 'Scaffold a project' }
sub description { 'Scaffold a project' }

sub opt_spec {
    return (
        [ 'cpanfile=s',   'cpanfile to configure from' ],
        [ 'spec-dir=s',   'directory to write the spec to (JSON files)' ],
        [ 'source-dir=s', 'directory to write the sources to (downloads if provided)' ],
        [ 'from-dir=s',   'directory to get sources from (optional)' ],
        [ 'additional-phase=s@',
          "additional phases to use ('develop' = author_requires, 'test' = test_requires). configure & runtime are done by default.",
        ],
        [ 'config|c=s',   'configuration file' ],
        [ 'verbose|v+',   'verbose output (can be provided multiple times)' ],
        [ 'add=s%',       '(deps) add the following dependency (phase=category/name=version[:release])' ],
        [ 'remove=s%',    '(deps) add the following dependency (phase=category/name=version[:release])' ],
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

    $self->_determine_config;
    $self->_validate_arg_command;
    $self->_validate_arg_from_dir;

    $self->{'config'}{'env'}{'cli'} = 1;

    $self->{'command'} eq 'add'    and $self->_validate_args_add;
    $self->{'command'} eq 'remove' and $self->_validate_args_remove;
    $self->{'command'} eq 'deps'   and $self->_validate_args_dependency;
}

sub execute {
    my $self = shift;

    my $package = Pakket::Package->new(
        'category' => $self->{'category'},
        'name'     => $self->{'module'}{'name'},
        'version'  => $self->{'module'}{'version'},
        'release'  => $self->{'module'}{'release'},
    );

    if ( $self->{'command'} eq 'add' ) {
        $self->_get_scaffolder->run;

    } elsif ( $self->{'command'} eq 'remove' ) {
        # TODO: check we are allowed to remove package (dependencies)
        $self->remove_package_spec($package);
        $self->remove_package_source($package);

    } elsif ( $self->{'command'} eq 'deps' ) {
        $self->{'deps_action'} eq 'add'
            and $self->add_package_dependency($package);

        $self->{'deps_action'} eq 'remove'
            and $self->remove_package_dependency($package);
    }
}


sub _determine_config {
    my $self = shift;

    my $config_file   = $self->{'opt'}{'config'};
    my $config_reader = Pakket::Config->new(
        $config_file ? ( 'files' => [$config_file] ) : (),
    );

    my $config = $config_reader->read_config;

    my %map = (
        'spec'   => [ 'spec_dir',   'ini' ],
        'source' => [ 'source_dir', 'spkt' ],
    );

    foreach my $type ( keys %map ) {
        my ( $opt_key, $opt_ext ) = @{ $map{$type} };
        my $directory = $self->{'opt'}{$opt_key};

        if ($directory) {
            $config->{'repositories'}{$type} = [
                'File',
                'directory'      => $directory,
                'file_extension' => $opt_ext,
            ];

            my $path = path($directory);
            $path->exists && $path->is_dir
                or $self->usage_error("Bad directory for $type repo: $path");
        }

        if ( !$config->{'repositories'}{$type} ) {
            $self->usage_error("Missing configuration for $type repository");
        }
    }

    $self->{'config'} = $config;
}

sub _validate_arg_command {
    my $self = shift;

    my $command = shift @{ $self->{'args'} }
        or $self->usage_error("Must pick action (add/remove/deps)");

    grep { $command eq $_ } qw< add remove deps >
        or $self->usage_error( "Wrong command (add/remove/deps)\n" );

    $self->{'command'} = $command;
}

sub _validate_arg_from_dir {
    my $self = shift;

    my $from_dir = $self->{'opt'}{'from_dir'};

    if ( $from_dir ) {
        path( $from_dir )->exists
            or $self->usage_error( "from-dir: $from_dir doesn't exist\n" );
        $self->{'from_dir'} = $from_dir;
    }
}

sub _validate_args_add {
    my $self = shift;

    my $cpanfile = $self->{'opt'}{'cpanfile'};

    if ( $cpanfile ) {
        $self->{'category'} = 'perl';
        $self->{'cpanfile'} = $cpanfile;
    } else {
        $self->_read_set_spec_str;
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
    $self->{'deps_action'} = $opt->{'add'} ? 'add' : 'remove';
}

sub _read_spec_str {
    my ( $self, $spec_str ) = @_;

    my ( $category, $name, $version, $release ) = $spec_str =~ PAKKET_PACKAGE_SPEC()
        or $self->usage_error("Provide [phase=]category/name[=version:release], not '$spec_str'");

    first { $_ eq $category } qw< perl > # add supported categories
        or $self->usage_error( "Wrong 'name' format\n" );

    return +{
        category => $category,
        name     => $name,
        version  => $version,
        release  => $release || 1,
    };
}

sub _read_set_spec_str {
    my $self = shift;

    my $spec_str = shift @{ $self->{'args'} };
    $spec_str or $self->usage_error( "Must provide a package id (category/name=version:release)" );
    $self->{'cpanfile'}
        and $self->usage_error( "You can't provide both a cpanfile and a package id." );

    my $spec = $self->_read_spec_str($spec_str);
    $self->{'category'} = delete $spec->{'category'};
    $self->{'module'}   = $spec;
}

sub _get_scaffolder {
    my $self = shift;

    $self->{'category'} eq 'perl'
        and return $self->_gen_scaffolder_perl;

    die "failed to create a scaffolder\n";
}

sub _gen_scaffolder_perl {
    my $self = shift;

    my @params = ( 'config' => $self->{'config'} );

    if ( $self->{'cpanfile'} ) {
        push @params =>
            ( 'cpanfile' => $self->{'cpanfile'} );

    } else {
        my $version = $self->{'module'}{'version'}
            # hack to pass exact version in prereq syntax
            ? '=='.$self->{'module'}{'version'}
            : undef;

        push @params => (
            'module'  => $self->{'module'}{'name'},
            'version' => $version,
        );
    }

    my $from_dir = $self->{'from_dir'};
    $from_dir and push @params => ( 'from_dir' => $from_dir );

    return Pakket::Scaffolder::Perl->new(@params);
}

sub remove_package_source {
    my ( $self, $package ) = @_;
    my $source_repo = $self->_get_repo('source');
    $source_repo->remove_package_source( $package );
    $log->info( sprintf("Removed %s from the source repo.", $package->id ) );
}

sub remove_package_spec {
    my ( $self, $package ) = @_;
    my $spec_repo = $self->_get_repo('spec');
    $spec_repo->remove_package_spec( $package );
    $log->info( sprintf("Removed %s from the spec repo.", $package->id ) );
}

sub add_package_dependency {
    my ( $self, $package ) = @_;
    $self->_package_dependency_edit($package,'add');
}

sub remove_package_dependency {
    my ( $self, $package ) = @_;
    $self->_package_dependency_edit($package,'remove');
}

sub _package_dependency_edit {
    my ( $self, $package, $cmd ) = @_;
    my $repo = $self->_get_repo('spec');
    my $spec = $repo->retrieve_package_spec($package);

    my $dep_name    = $self->{'dependency'}{'name'};
    my $dep_version = $self->{'dependency'}{'version'};

    my ( $category, $phase ) = @{ $self->{'dependency'} }{qw< category phase >};

    my $dep_exists = ( defined $spec->{'Prereqs'}{$category}{$phase}{$dep_name}
        and $spec->{'Prereqs'}{$category}{$phase}{$dep_name}{'version'} eq $dep_version );

    if ( $cmd eq 'add' ) {
        if ( $dep_exists ) {
            $log->info( sprintf("%s is already a %s dependency for %s.",
                                $dep_name, $phase, $package->name) );
            exit 1;
        }

        $spec->{'Prereqs'}{$category}{$phase}{$dep_name} = +{
            version => $dep_version
        };

        $log->info( sprintf("Added %s as %s dependency for %s.",
                            $dep_name, $phase, $package->name) );

    } elsif ( $cmd eq 'remove' ) {
        if ( !$dep_exists ) {
            $log->info( sprintf("%s is not a %s dependency for %s.",
                                $dep_name, $phase, $package->name) );
            exit 1;
        }

        delete $spec->{'Prereqs'}{$category}{$phase}{$dep_name};

        $log->info( sprintf("Removed %s as %s dependency for %s.",
                            $dep_name, $phase, $package->name) );
    }

    $repo->store_package_spec($package, $spec);
}

sub _get_repo {
    my ( $self, $key ) = @_;
    my $class = 'Pakket::Repository::' . ucfirst($key);
    return $class->new(
        'backend' => $self->{'config'}{'repositories'}{$key},
    );
}

1;
__END__

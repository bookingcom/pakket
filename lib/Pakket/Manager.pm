package Pakket::Manager;
# ABSTRACT: Manage pakket packages and repos

use Moose;
use Log::Any qw< $log >;
use Carp     qw< croak >;
use Safe::Isa;

use Pakket::Log;
use Pakket::Scaffolder::Native;
use Pakket::Scaffolder::Perl;

has 'config' => (
    'is'        => 'ro',
    'isa'       => 'HashRef',
    'default'   => sub { +{} },
);

has 'category' => (
    'is'        => 'ro',
    'isa'       => 'Str',
    'lazy'      => 1,
    'builder'   => '_build_category',
);

has 'cache_dir' => (
    'is'        => 'ro',
    'isa'       => 'Maybe[Str]',
);

has 'cpanfile' => (
    'is'        => 'ro',
    'isa'       => 'Maybe[Str]',
);

has 'package' => (
    'is'        => 'ro',
);

has 'phases' => (
    'is'        => 'ro',
    'isa'       => 'Maybe[ArrayRef]',
);

has 'file_02packages' => (
    'is'        => 'ro',
    'isa'       => 'Maybe[Str]',
);

has 'no_deps' => (
    'is'        => 'ro',
    'isa'       => 'Bool',
    'default'   => 0,
);

has 'is_local' => (
    'is'        => 'ro',
    'isa'       => 'HashRef',
    'default'   => sub { +{} },
);

has 'requires_only' => (
    'is'        => 'ro',
    'isa'       => 'Bool',
    'default'   => 0,
);

has 'no_bootstrap' => (
    'is'        => 'ro',
    'isa'       => 'Bool',
    'default'   => 0,
);

has 'source_archive' => (
    'is'        => 'ro',
    'isa'       => 'Maybe[Str]',
);

has 'custom_spec' => (
    'is'        => 'ro',
    'isa'       => 'Maybe[HashRef]',
);

sub _build_category {
    my $self = shift;
    $self->{'cpanfile'} and return 'perl';
    $self->{'custom_spec'} and return $self->{'custom_spec'}{Package}{category};
    return $self->package->category;
}

sub list_ids {
    my ( $self, $type ) = @_;
    my $repo = $self->_get_repo($type);
    print "$_\n" for sort @{ $repo->all_object_ids };
}

sub show_package_config {
    my $self = shift;
    my $repo = $self->_get_repo('spec');
    my $spec = $repo->retrieve_package_spec( $self->package );

    my ( $category, $name, $version, $release ) =
        @{ $spec->{'Package'} }{qw< category name version release >};

    print <<"SHOW";

# PACKAGE:

category: $category
name:     $name
version:  $version
release:  $release

# DEPENDENCIES:

SHOW

    for my $c ( sort keys %{ $spec->{'Prereqs'} } ) {
        for my $p ( sort keys %{ $spec->{'Prereqs'}{$c} } ) {
            print "$c/$p:\n";
            for my $n ( sort keys %{ $spec->{'Prereqs'}{$c}{$p} } ) {
                my $v = $spec->{'Prereqs'}{$c}{$p}{$n}{'version'};
                print "- $n-$v\n";
            }
            print "\n";
        }
    }

    if ($spec->{'build_opts'}) {
        print "build options:\n";
        if ($spec->{'build_opts'}{'configure_flags'}) {
            print "    configure flags:\n";
            for my $flag (@{$spec->{'build_opts'}{'configure_flags'}}) {
                print "        $flag\n";
            }
        }
        if ($spec->{'build_opts'}{'build_flags'}) {
            print "    build flags:\n";
            for my $flag (@{$spec->{'build_opts'}{'build_flags'}}) {
                print "        $flag\n";
            }
        }
        if ($spec->{'build_opts'}{'env_vars'}) {
            print "    env vars:\n";
            for my $var (keys %{$spec->{'build_opts'}{'env_vars'}}) {
                my $value = $spec->{'build_opts'}{'env_vars'}{$var};
                print "        $var=$value\n";
            }
        }
        if ($spec->{'build_opts'}{'pre_build'}) {
            print "    pre build commands:\n";
            for my $cmd (@{$spec->{'build_opts'}{'pre_build'}}) {
                print "        " . join(" ", @{$cmd}) . "\n";
            }
        }
        if ($spec->{'build_opts'}{'post_build'}) {
            print "    post build commands:\n";
            for my $cmd (@{$spec->{'build_opts'}{'post_build'}}) {
                print "        " . join(" ", @{$cmd}) . "\n";
            }
        }
        print "\n";
    }

    # TODO: reverse dependencies (requires map)
}

sub show_package_deps {
    my $self = shift;

    my $SPACES = "  ";
    my @queue = ({package => $self->package, level => 0});
    my $repo = $self->_get_repo('spec');
    my %seen;
    while (0+@queue) {
        my $entry = pop @queue;
        my $spaces = $SPACES x $entry->{'level'};

        # text entry: configure or runtime
        if ( my $type = $entry->{'type'} ) {
            print $spaces ."$type:\n";
            next;
        }

        my $package = $entry->{'package'};
        my $exists = $seen{$package->short_name} ? " (exists)" : "" ;
        print $spaces . $package->id . "$exists\n";

        $exists and next;

        $seen{$package->short_name}=1;
        my @deps;
        my $level = $entry->{'level'} + 1;
        my $spec = $repo->retrieve_package_spec( $package );
        my $prereq = $spec->{'Prereqs'};
        for my $category (sort keys %$prereq) {
            for my $type (sort keys %{$prereq->{$category}}) {
                unshift @deps, {'level'=> $level,'type'=>$type};
                for my $name (sort keys %{$prereq->{$category}{$type}}) {
                    my $req_ver = $prereq->{$category}{$type}{$name}{'version'};

                    my $ver_rel = $repo->latest_version_release(
                                            $category, $name, $req_ver);

                    my ( $version, $release ) = @{$ver_rel};

                    my $req = Pakket::PackageQuery->new(
                                    'category' => $category,
                                    'name'     => $name,
                                    'version'  => $version,
                                    'release'  => $release,
                                );
                    unshift @deps, {'level'=> $level+1, 'package'=>$req};
                }
            }
        }

        push @queue, @deps;
    }
}

sub add_package {
    my $self = shift;
    my $errors = $self->_get_scaffolder->run;
    $errors && exit(1);
}

sub remove_package {
    my ( $self, $type ) = @_;
    my $repo = $self->_get_repo( $type );
    $repo->remove_package_file( $type, $self->package );
    $log->info( sprintf("Removed %s from the %s repo.", $self->package->id, $type ) );
}

sub add_dependency {
    my ( $self, $dependency ) = @_;
    $self->_package_dependency_edit($dependency, 'add');
}

sub remove_dependency {
    my ( $self, $dependency ) = @_;
    $self->_package_dependency_edit($dependency, 'remove');
}

sub _package_dependency_edit {
    my ( $self, $dependency, $cmd ) = @_;
    my $repo = $self->_get_repo('spec');
    my $spec = $repo->retrieve_package_spec( $self->package );

    my $dep_name    = $dependency->{'name'};
    my $dep_version = $dependency->{'version'};

    my ( $category, $phase ) = @{$dependency}{qw< category phase >};

    my $dep_exists = ( defined $spec->{'Prereqs'}{$category}{$phase}{$dep_name} );

    my $name = $self->package->name;

    if ( $cmd eq 'add' ) {
        if ( $dep_exists ) {
            $log->info( sprintf("%s is already a %s dependency for %s.",
                                $dep_name, $phase, $name) );
            exit 1;
        }

        $spec->{'Prereqs'}{$category}{$phase}{$dep_name} = +{
            version => $dep_version
        };

        $log->info( sprintf("Added %s as %s dependency for %s.",
                            $dep_name, $phase, $name) );

    } elsif ( $cmd eq 'remove' ) {
        if ( !$dep_exists ) {
            $log->info( sprintf("%s is not a %s dependency for %s.",
                                $dep_name, $phase, $name) );
            exit 1;
        }

        delete $spec->{'Prereqs'}{$category}{$phase}{$dep_name};

        $log->info( sprintf("Removed %s as %s dependency for %s.",
                            $dep_name, $phase, $name) );
    }

    $repo->store_package_spec($self->package, $spec);
}

sub _get_repo {
    my ( $self, $key ) = @_;
    my $class = 'Pakket::Repository::' . ucfirst($key);
    return $class->new(
        'backend' => $self->config->{'repositories'}{$key},
    );
}

sub _get_scaffolder {
    my $self = shift;

    $self->category eq 'perl'
        and return $self->_gen_scaffolder_perl;
    $self->category eq 'native'
        and return $self->_gen_scaffolder_native;

    croak("Scaffolder for category " . $self->category . " doesn't exist");
}

sub _gen_scaffolder_perl {
    my $self = shift;

    my %params = (
        'config'   => $self->config,
        'phases'   => $self->phases,
        'no_deps'  => $self->no_deps,
        'is_local' => $self->is_local,
        ( 'types'  => ['requires'] )x!! $self->requires_only,
    );

    if ( $self->cpanfile ) {
        $params{'cpanfile'} = $self->cpanfile;
    } elsif ( $self->custom_spec ) {
        $params{'custom_spec'} = $self->custom_spec;
    } else {
        $params{'module'} = $self->package;
    }

    $self->cache_dir
        and $params{'cache_dir'} = $self->cache_dir;

    $self->file_02packages
        and $params{'file_02packages'} = $self->file_02packages;

    $self->no_bootstrap
        and $params{'no_bootstrap'} = $self->no_bootstrap;

    return Pakket::Scaffolder::Perl->new(%params);
}

sub _gen_scaffolder_native {
    my $self = shift;

    my $name = $self->package->name;
    my $version = $self->package->version;

    my %params = (
        'package'         => $self->package,
        'source_archive'  => $self->source_archive,
        'config'          => $self->config,
    );

    return Pakket::Scaffolder::Native->new(%params);
}

__PACKAGE__->meta->make_immutable;

no Moose;

1;

__END__

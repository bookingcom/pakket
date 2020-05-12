package Pakket::Controller::Build;

# ABSTRACT: Build pakket packages

use v5.22;
use Moose;
use MooseX::Clone;
use MooseX::StrictConstructor;
use namespace::autoclean;

# core
use File::Spec;
use List::Util qw(any);
use experimental qw(declared_refs refaliasing signatures);

# non core
use JSON::MaybeXS qw(decode_json);
use Module::Runtime qw(use_module);
use Path::Tiny;

# local
use Pakket::Controller::Install;
use Pakket::Type::Package;
use Pakket::Type::PackageQuery;

use constant {
    'BUILD_DIR_TEMPLATE' => 'pakket-build-%s-XXXXXX',
    'DEFAULT_PREFIX'     => $ENV{'PERL_LOCAL_LIB_ROOT'} || '~/perl5',
};

has [qw(keep)] => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'default' => 0,
);

has [qw(overwrite)] => (
    'is'      => 'ro',
    'isa'     => 'Int',
    'default' => 0,
);

has [qw(no_man no_test)] => (
    'is'  => 'ro',
    'isa' => 'Int',
);

has [qw(prefix)] => (
    'is'  => 'ro',
    'isa' => 'Maybe[Str]',
);

has '_builders_cache' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'lazy'    => 1,
    'default' => sub {+{}},
);

has 'installer' => (
    'is'      => 'ro',
    'isa'     => 'Maybe[Pakket::Controller::Install]',
    'lazy'    => 1,
    'clearer' => '_clear_installer',
    'default' => sub ($self) {
        return Pakket::Controller::Install->new(
            'pakket_dir'  => path(File::Spec->devnull),                        # installer is unable install by default
            'parcel_repo' => $self->parcel_repo,
            'phases'      => $self->phases,
            $self->%{qw(config log log_depth)},
        );
    },
);

with qw(
    MooseX::Clone
    Pakket::Controller::Role::CanProcessQueries
    Pakket::Role::CanBundle
    Pakket::Role::CanFilterRequirements
    Pakket::Role::HasConfig
    Pakket::Role::HasLog
    Pakket::Role::HasParcelRepo
    Pakket::Role::HasSourceRepo
    Pakket::Role::HasSpecRepo
    Pakket::Role::RunCommand
);

sub execute ($self, %params) {
    return $self->_execute(%params);
}

sub process_query ($self, $query, %params) {
    my $id      = $query->short_name;
    my $builder = $self->_get_builder($query->category);
    $builder->exclude_packages->{$query->name}
        and $self->log->info('Package is excluded form build, skipping:', $id)
        and return;

    if ($query->as_prereq) {
        my (\@found, undef) = $self->filter_packages_in_cache({$id => $query}, $params{'processing'} // {});
        @found
            and $self->log->info('Skipping as we already processed or scheduled processing:', $id)
            and return;
    }

    if (!exists $params{'build_dir'}) {
        $params{'build_dir'}
            = Path::Tiny->tempdir(sprintf (BUILD_DIR_TEMPLATE(), $query->name), 'CLEANUP' => !$self->keep);
        $params{'processing'} = {$builder->bootstrap_processing->%*};
    }
    $params{'prefix'}  //= path($self->prefix || DEFAULT_PREFIX())->absolute;
    $params{'pkg_dir'} //= $params{'build_dir'}->child($params{'prefix'})->absolute;

    if ($self->overwrite <= $query->as_prereq && $self->installer) {
        if (my @found = $self->parcel_repo->filter_queries([$query])) {
            if (!$query->as_prereq) {
                $self->log->info('Skipping as we already have parcel available:', $found[0]->id);
                return;
            }
            $self->log->notice('Installing package:', $id);
            $self->_do_install_package($found[0], %params);
            return;
        }
    }

    my @found = $self->spec_repo->filter_queries([$query])
        or $self->croak('Spec is not found for:', $id);

    $self->log->notice('Building package:', $id);
    $self->_do_build_package($found[0], %params);
    return;
}

sub _do_install_package ($self, $package, %params) {
    $params{'processing'}{$package->short_name}{$package->version}{$package->release} = 1;
    my $parcel_dir = $self->parcel_repo->retrieve_package_file($package);
    my $spec_file  = $parcel_dir->child(PARCEL_FILES_DIR(), PARCEL_METADATA_FILE());
    my $spec       = decode_json($spec_file->slurp_utf8);

    # Generate a Package instance from the spec using the information we have on it
    $package = Pakket::Type::Package->new_from_specdata($spec, $package->%{qw(as_prereq)});

    if (!$params{'no_prereqs'}) {
        $self->process_prereqs(
            $package,
            %params,
            'phases' => $params{'phases'} // $self->phases,
            'types'  => $params{'types'}  // $self->types,
        );
    }

    $self->log->info('Processing parcel:', $package->id, ('(as prereq)') x !!$package->as_prereq);
    $self->installer->install_parcel($package, $parcel_dir, $params{'pkg_dir'});
    return;
}

sub _do_build_package ($self, $package, %params) {
    $params{'processing'}{$package->short_name}{$package->version}{$package->release} = 1;

    # Generate a Package instance from the spec using the information we have on it
    $package = $self->spec_repo->gen_package($package);

    # step I recursively build all necessary prereqs
    if (!$params{'no_prereqs'} || $params{'prereqs_only'}) {
        $self->process_prereqs(
            $package,
            %params,
            'phases' => $params{'phases'} // $self->phases,
            'types'  => $params{'types'}  // $self->types,
        );
    }

    $params{'prereqs_only'} && !$package->as_prereq
        and return;                                                            # done building prereqs

    # step II build the package itself
    $self->snapshot_build_dir($package, $params{'pkg_dir'}, 1);                # save directory state before installing into it

    $self->_process_package(
        $package,
        %params{qw(pkg_dir prefix)},
        'use_prefix' => !!$self->prefix,
        'sources'    => $self->source_repo->retrieve_package_file($package),
        %params{qw(build_dir)},
    );

    my $package_files = $self->snapshot_build_dir($package, $params{'pkg_dir'});

    $self->log->notice('Bundling:', $package->id);
    $self->bundle($package, $params{'pkg_dir'}, $package_files);

    $self->succeeded->{$package->id}++;

    return;
}

sub _process_package ($self, $package, %params) {
    my $builder = $self->_get_builder($package->category);

    $package->pakket_meta
        or $self->croak('Unable to find metadata');

    my $metadata = $package->pakket_meta->build        // {};
    my $config   = $self->config->{$package->category} // {};

    $self->log->notice('Building:', $package->id);
    $builder->execute(
        'name'     => $package->name,
        'metadata' => $metadata,
        'no-man'   => $self->no_man // $metadata->{'no-man'} // $config->{'build'}{'no-man'} // 0,
        'no-test'  => $self->no_test // $metadata->{'no-test'} // $config->{'build'}{'no-test'} // 0,
        %params{qw(build_dir pkg_dir prefix use_prefix sources)},
    );

    return;
}

sub _get_builder ($self, $category) {
    exists $self->_builders_cache->{$category}
        and return $self->_builders_cache->{$category};

    my @valid_categories = qw(native perl);

    any {$category eq $_} @valid_categories
        or $self->croak('I do not have a builder for category:', $category);

    my $builder = $self->_builders_cache->{$category}
        = use_module(sprintf ('%s::%s', __PACKAGE__, ucfirst $category))->new($self->%{qw(config log log_depth)});

    $self->log->notice('Bootstrapping builder started:', $builder->type);
    $self->_bootstrap_builder($builder);
    $self->log->notice('All bootstrap modules are prepared for:', $builder->type);

    return $builder;
}

sub _bootstrap_builder ($self, $builder) {
    my ($modules, $requirements) = $builder->bootstrap_prepare_modules();
    $modules && $modules->@*
        or return;

    {
        my (\@found, \@not_found) = $self->parcel_repo->filter_requirements({$requirements->%*});
        if (@not_found) { ## if even one of bootstrap packages not found we shoud rebuild whole bootstrap environment
            $self->log->notice('Bootstrapping builder started:', $builder->type);
            $builder->bootstrap($self, $modules, $requirements);
            $self->log->notice('Bootstrapping builder finished:', $builder->type);
        }
    }

    # now all packages exist let's just install them into bootstrap dir
    $self->log->notice('Install bootsrap modules for:', $builder->type);
    my (\@found, undef) = $self->parcel_repo->filter_requirements($requirements);
    my $prefix  = path($self->prefix || DEFAULT_PREFIX())->absolute;
    my $pkg_dir = $builder->bootstrap_dir->child($prefix)->absolute;
    foreach my $package (@found) {
        $self->log->notice('Installing package:', $package->id);
        $self->_do_install_package(
            $package,
            'build_dir'  => $builder->bootstrap_dir,
            'pkg_dir'    => $builder->bootstrap_dir,
            'processing' => $builder->bootstrap_processing,
        );
    }

    return;
}

before [qw(_do_build_package _do_install_package _bootstrap_builder)] => sub ($self, @) {
    return $self->log_depth_change(+1);
};

after [qw(_do_build_package _do_install_package _bootstrap_builder)] => sub ($self, @) {
    return $self->log_depth_change(-1);
};

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 SYNOPSIS

    use Pakket::Builder;
    my $builder = Pakket::Builder->new();
    $builder->execute();

=head1 DESCRIPTION

The L<Pakket::Builder> is in charge of building a Pakket package. It is
normally accessed with the C<pakket install> command. Please see
L<pakket> for the command line interface. Specifically
L<Pakket::Command::install> for the C<install> command
documentation.

The building includes bootstrapping any toolchain systems (currently
only applicable to Perl) and then building all packages specifically.

The installer (L<Pakket::Controller::Install>) can be used to install pre-built
packages.

Once the building is done, the files and their manifest is sent to the
bundler (L<Pakket::Role::CanBundle>) in order to create the final parcel. The
parcel will be stored in the appropriate storage, based on your
configuration.

=head1 ATTRIBUTES

=head2 config

A configuration hashref populated by L<Pakket::Config> from the config file.

Read more at L<Pakket::Role::HasConfig>.

=head2 installer

The L<Pakket::Installer> object used for installing any pre-built
parcels during the build phase.

=head2 keep

A boolean that controls whether the build dir will be deleted or
not. This is useful for debugging.

Default: B<0>.

=head2 parcel_repo

See L<Pakket::Role::HasParcelRole>.

=head2 parcel_repo_backend

See L<Pakket::Role::HasParcelRole>.

=head2 source_repo

See L<Pakket::Role::HasSourceRole>.

=head2 source_repo_backend

See L<Pakket::Role::HasSourceRole>.

=head2 spec_repo

See L<Pakket::Role::HasSpecRole>.

=head2 spec_repo_backend

See L<Pakket::Role::HasSpecRole>.

=head1 METHODS

=head2 bootstrap_builder()

Build all the packages to bootstrap a build environment. This would
include any toolchain packages necessary.

    $builder->bootstrap_builder();

This procedure requires three steps:

=over 4

=item 1.

First, we build the bootstrapping packages within the context of the
builder. However, they will depend on any libraries or applications
already available in the current environment. For example, in a Perl
environment, it will use core modules available with the existing
interpreter.

They will need to be built without any dependencies. Since they assume
on the available dependencies in the system, they will build
succesfully.

=item 2.

Secondly, we build their dependencies only. This will allow us to then
build on top of them the original bootstrapping modules, thus
separating them from the system entirely.

=item 3.

Lastly, we repeat the first step, except with dependencies, and
explicitly preferring the dependencies we built at step 2.

=back

=head2 execute()

The main method of the class. Sets up the bootstrapping and calls
C<_process_queries>.

    my $pkg_query = Pakket::Type::PackageQuery->new(...);
    $builder->execute('queries' => \@pkg_queries);
    $builder->execute('prereqs' => \%prereqs);

See L<Pakket::Type::PackageQuery> on defining a query for a package.

=cut

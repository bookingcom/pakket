package Pakket::Controller::Scaffold;

# ABSTRACT: Scaffold package source and spec

use v5.22;
use Moose;
use MooseX::Clone;
use MooseX::StrictConstructor;
use namespace::autoclean;

# core
use List::Util qw(any);
use experimental qw(declared_refs refaliasing signatures);

# non core
use Module::Runtime qw(use_module);

# local
use Pakket::Type::PackageQuery;

has [qw(dry_run)] => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'default' => 0,
);

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

has [qw(cpan_02packages)] => (
    'is'  => 'ro',
    'isa' => 'Maybe[Str]',
);

has '_scaffolders_cache' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'lazy'    => 1,
    'default' => sub {+{}},
);

with qw(
    MooseX::Clone
    Pakket::Controller::Role::CanProcessQueries
    Pakket::Role::CanFilterRequirements
    Pakket::Role::CanVisitPrereqs
    Pakket::Role::HasConfig
    Pakket::Role::HasLog
    Pakket::Role::HasSourceRepo
    Pakket::Role::HasSpecRepo
    Pakket::Role::Perl::BootstrapModules
    Pakket::Role::Perl::HasCpan
);

sub process_query ($self, $query, %params) {
    my $id = $query->short_name;

    { ## check processed packages
        my (\@found, undef) = $self->filter_packages_in_cache({$id => $query}, $params{'processing'} // {});
        @found
            and $self->log->info('Skipping as we already processed or scheduled processing:', $id)
            and return;
    }

    { ## check existing packages
        if ($self->overwrite <= $query->as_prereq) {                           # if overwrite < 2 do not rebuild prereqs
            my ($package) = $self->spec_repo->filter_queries([$query]);
            $package
                and $self->log->notice('Skipping as we already have spec:', $package->id)
                and return;
        }
    }

    $self->log->noticef('Scaffolding package: %s=%s', $id, $query->requirement);
    $self->_do_scaffold_query($query, %params);
    return;
}

sub _do_scaffold_query ($self, $query, %params) {
    my $scaffolder = $self->_get_scaffolder($query->category);

    my $package = $scaffolder->execute($query, \%params);

    $params{'processing'}{$package->short_name}{$package->version}{$package->release} = 1;

    if (!$params{'no_prereqs'}) {
        $self->process_prereqs(
            $package,
            %params,
            'phases' => $params{'phases'} // $self->phases,
            'types'  => $params{'types'}  // $self->types,
        );
    }

    if ($self->dry_run) {
        $self->log->notice('Dry run, not saving:', $package->id);
    } else {
        $self->log->notice('Saving spec   for:', $package->id);
        $self->add_spec_for_package($package);
        $self->log->notice('Saving source for:', $package->id);
        $self->add_source_for_package($package, $params{'sources'});
    }

    $self->succeeded->{$package->id}++;

    return;
}

sub _get_scaffolder ($self, $category) {
    exists $self->_scaffolders_cache->{$category}
        and return $self->_scaffolders_cache->{$category};

    my @valid_categories = qw(native perl);

    any {$category eq $_} @valid_categories
        or $self->croak('I do not have a builder for category:', $category);

    my $scaffolder = $self->_scaffolders_cache->{$category}
        = use_module(sprintf ('%s::%s', __PACKAGE__, ucfirst $category))->new($self->%{qw(config log log_depth)});

    $self->_bootstrap_scaffolder($scaffolder);

    return $scaffolder;
}

sub _bootstrap_scaffolder ($self, $scaffolder) {
    my ($modules, $requirements) = $scaffolder->bootstrap_prepare_modules();
    $modules && $modules->@*
        or return;

    my (\@found, \@not_found) = $self->spec_repo->filter_requirements({$requirements->%*});
    if (@not_found) { ## if even one of bootstrap packages not found we shoud rebuild whole bootstrap environment
        $self->log->notice('Bootstrapping scaffolder started:', $scaffolder->type);
        $scaffolder->bootstrap($self, $modules, $requirements);
        $self->log->notice('Bootstrapping scaffolder finished:', $scaffolder->type);
    }

    return;

}

before [qw(_do_scaffold_query)] => sub ($self, @) {
    return $self->log_depth_change(+1);
};

after [qw(_do_scaffold_query)] => sub ($self, @) {
    return $self->log_depth_change(-1);
};

__PACKAGE__->meta->make_immutable;

1;

__END__

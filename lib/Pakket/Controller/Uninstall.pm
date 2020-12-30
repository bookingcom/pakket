package Pakket::Controller::Uninstall;

# ABSTRACT: Uninstall pakket packages

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

# core
use Carp;
use English qw(-no_match_vars);
use experimental qw(declared_refs refaliasing signatures);

# non core
use Path::Tiny;

# local
use Pakket::Log;

has [qw(atomic)] => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'default' => 1,
);

has [qw(dry_run no_prereqs)] => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'default' => 0,
);

has '_state' => (
    'is'      => 'rw',
    'isa'     => 'HashRef',
    'default' => sub {+{}},
);

with qw(
    Pakket::Controller::Role::CanProcessQueries
    Pakket::Role::CanFilterRequirements
    Pakket::Role::CanUninstallPackage
    Pakket::Role::CanVisitPrereqs
    Pakket::Role::HasConfig
    Pakket::Role::HasInfoFile
    Pakket::Role::HasLibDir
    Pakket::Role::HasLog
);

sub execute ($self, %params) {
    $self->_state->{'info_file'} = $self->load_info_file($self->active_dir);

    my $result = $self->process_queries(%params);

    if ($result == 0) {                                                        # do changes persistent only if no falures
        $self->save_info_file($self->work_dir, $self->_state->{'info_file'});
        $self->set_rollback_tag($self->work_dir, $self->rollback_tag);
        $self->activate_work_dir;
    }

    return $result;
}

sub check_queries_before_processing ($self, $queries, %params) {
    my \%requirements = as_requirements($queries);
    my (\@found, \@not_found) = $self->filter_packages_in_cache(\%requirements, $self->all_installed_cache);
    if (@not_found) {
        $self->croak("Following packages are not installed: @{[ map $_->id, @not_found ]}");
    }

    $self->log->notice("Going to uninstall following packages: @{[ map $_->id, @found ]}");
    $queries->@* = @found;                                                     # substitute queries for packages here

    return scalar @found;
}

sub process_query ($self, $package, %params) {
    $self->log->notice('Uninstalling:', $package->id);

    if (!$self->no_prereqs) {
        $self->log->warn('Uninstalling prereqs is not implemented yet');

        # $self->_process_prereqs($package);
    }

    $self->uninstall_package($self->_state->{'info_file'}, $package);
    $self->succeeded->{$package->id}++;

    return;
}

# sub _process_prereqs ($self, $package) {
# my \%installed_packages = $self->_state->{'info_file'}{'installed_packages'};
# my \%prereqs            = delete $installed_packages{$package->category}{$package->name}{'prereqs'};
#
# $self->visit_prereqs(
# \%prereqs,
# sub ($phase, $type, $module, $version) {
# my ($category, $name) = $module =~ m{(.+)/(.+)}x;
# if (--$installed_packages{$category}{$name}{'as_prereq'} < 1) {
# $self->log->notice('Uninstalling:', $category, $name);
# }
# },
# );
#
# return;
# }

__PACKAGE__->meta->make_immutable;

1;

__END__

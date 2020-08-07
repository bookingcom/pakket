package Pakket::Role::CanFilterRequirements;

# ABSTRACT: Role can process requirements list and filter it

use v5.22;
use Moose::Role;
use namespace::autoclean;

# core
use Carp;
use experimental qw(declared_refs refaliasing signatures);

# local
use Pakket::Helper::Versioner;
use Pakket::Type::Package;
use Pakket::Type::PackageQuery;
use Pakket::Utils::Package;

has 'versioners' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'lazy'    => 1,
    'builder' => '_build_versioners',
);

sub as_requirements ($queries) {
    my %result = map {$_->short_name => $_} $queries->@*;
    carp('Requirement redefinition, should never happen and must be fixed')
        if scalar $queries->@* != scalar keys %result;
    return \%result;
}

sub is_package_in_cache ($self, $package, $cache) {
    my %requirements = ($package->short_name => Pakket::Type::PackageQuery->new_from_string($package->id));

    my (\@found, undef) = $self->filter_packages_in_cache(\%requirements, $cache);

    return scalar @found;
}

sub filter_packages_in_cache ($self, $requirements, $cache) {
    my \%requirements = $requirements;

    my @found;                                                                 # packages
    my @not_found;                                                             # requirements
    foreach my $short_name (sort keys %requirements) {
        my \$requirement = \$requirements{$short_name};

        # $self->log->tracef('searching in cache: %s', $requirement->id);

        my $package = exists $cache->{$short_name} && $self->select_best_package($requirement, $cache->{$short_name})
            or push (@not_found, $requirement)
            and next;

        push (@found, $package);
        delete $requirements{$short_name};
    }

    return \@found, \@not_found;
}

sub select_best_package ($self, $requirement, $package_cache) {
    $package_cache
        or return;

    my ($version, $r) = $self->select_best_version_from_cache($requirement, $package_cache)
        or return;

    $requirement->release && !exists $r->{$requirement->release}
        and return;

    my $desired_release = $requirement->release || (sort keys $r->%*)[-1];

    my $result = Pakket::Type::Package->new(
        $requirement->%{qw(category name as_prereq)},
        'version' => $version,
        'release' => $desired_release,
    );

    $self->log->tracef('requirement %s %s matched to: %s',
        $requirement->short_name, $requirement->conditions, $result->id);
    return $result;
}

sub select_best_version_from_cache ($self, $requirement, $package_cache) {
    $requirement->isa('Pakket::Type::PackageQuery')
        or confess('should be only Pakket::Type::PackageQuery');

    $package_cache
        or return;

    my \%cache = $package_cache;

    my @versions = sort keys %cache;
    $self->log->tracef('matching requirement %s %s to: %s',
        $requirement->name, $requirement->conditions, join (' ', @versions));
    @versions = $self->versioners->{$requirement->category}->select_versions($requirement->conditions, \@versions)
        or return;

    my $latest_version
        = @versions == 1
        ? $versions[0]
        : $self->versioners->{$requirement->category}->select_latest(\@versions);

    #$self->log->tracef('requirement %s matched to: %s', $requirement->conditions, $latest_version);

    return %cache{$latest_version};
}

sub available_variants ($self, $package_cache) {
    $package_cache && $package_cache->%*
        or return ();

    my \%variants = $package_cache;
    my @result;
    foreach my $version (keys %variants) {
        push (@result, map {"$version:$_"} keys $variants{$version}->%*);
    }
    return @result;
}

sub is_package_available ($self, $package) {
    my @versions = $self->available_variants($self->all_objects_cache->{$package->short_name})
        or return;

    $self->versioners->{$package->category}->is_satisfying($package->variant, @versions)
        and return 1;

    return;
}

sub _build_versioners ($self) {
    my $perl_versioner = Pakket::Helper::Versioner->new('type' => 'Perl');     # use same versioner for perl and native
    return {
        'perl'   => $perl_versioner,
        'native' => $perl_versioner,
    };
}

1;

package Pakket::Utils::DependencyBuilder;

# ABSTRACT: DependencyBuilder utility functions

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

# local
use Pakket::Type::Package;
use Pakket::Type::PackageQuery;

# core
use experimental qw(declared_refs refaliasing signatures);

with qw(
    Pakket::Role::CanFilterRequirements
    Pakket::Role::CanVisitPrereqs
    Pakket::Role::HasLog
    Pakket::Role::HasSpecRepo
);

sub recursive_requirements ($self, $queries, %params) {
    $params{'parcel_repo'}
        or $self->croak('Undefined parcel repo');

    my %result;

    my \@queries = $queries;
    while (@queries) {
        my \%requirements = as_requirements(\@queries);

        $self->filter_packages_in_cache(\%requirements, \%result);
        my \@packages = $params{'parcel_repo'}->select_available_packages(\%requirements);

        @queries = ();
        foreach my $pkg (@packages) {
            my $spec    = $self->spec_repo->retrieve_package($pkg);
            my $package = Pakket::Type::Package->new_from_specdata($spec);
            $result{$package->short_name}{$package->version}{$package->release} //= $pkg;

            my $meta = $package->pakket_meta->prereqs
                or next;

            $self->log->infof('Prereqs for: %s', $package->id);

            $self->log_depth_change(+1);
            $self->visit_prereqs(
                $meta,
                sub ($phase, $type, $name, $requirement) {
                    $self->log->infof('Found prereq %9s %10s: %s=%s', $phase, $type, $name, $requirement);
                    push (
                        @queries,
                        Pakket::Type::PackageQuery->new_from_string(
                            "$name=$requirement",
                            'as_prereq' => 1,
                        ),
                    );
                },
                'phases' => $params{'phases'},
                'types'  => $params{'types'},
            );
            $self->log_depth_change(-1);
        }
    }

    return \%result;
}

sub validate_requirements ($self, $requirements) {
    my @result;
    foreach my $short_name (sort keys $requirements->%*) {
        my \%versions = $requirements->{$short_name};
        %versions == 1
            or $self->croak('Package has ambigious versions:', $short_name, keys %versions);
        my (\%releases) = values %versions;
        %releases == 1
            or $self->croak('Package has ambigious release:', $short_name, keys %versions, keys %releases);
        push (@result, values %releases);
    }

    return \@result;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

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
    while (@queries) {                                                         # here might be queries with same short_name (from different dependencies)
        my \%requirements = as_requirements([shift @queries]);

        $self->filter_packages_in_cache(\%requirements, \%result);
        my \@packages = $params{'parcel_repo'}->select_available_packages(\%requirements);

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
    my %failures;
    foreach my $short_name (sort keys $requirements->%*) {
        my \%versions = $requirements->{$short_name};
        %versions == 1
            or $failures{$short_name} = $requirements->{$short_name} and next;
        my (\%releases) = values %versions;
        %releases == 1
            or $failures{$short_name} = $requirements->{$short_name} and next;
        push (@result, values %releases);
    }

    if (%failures) {
        my $whole_message = '';
        foreach my $short_name (sort keys %failures) {
            my \%versions = $failures{$short_name};
            if (%versions != 1) {
                my $msg = join (' ', $short_name, sort keys %versions);
                $self->log->critical('Package has ambigious versions:', $msg);
                $whole_message = join ("\n", $whole_message, $msg);
                next;
            }
            my (\%releases) = values %versions;
            if (%releases != 1) {
                my $msg = join (' ', $short_name, sort keys %versions, sort keys %releases);
                $self->log->critical('Package has ambigious release:', $msg);
                $whole_message = join ("\n", $whole_message, $msg);
            }
        }
        $self->croak("Package(s) version/release ambiguity:$whole_message");
    }

    return \@result;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

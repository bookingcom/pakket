package Pakket::Role::HasSpecRepo;
# ABSTRACT: Provide spec repo support

use v5.22;
use Moose::Role;
use Pakket::Repository::Spec;
use Log::Any              qw< $log >;

use Pakket::Constants;

has 'spec_repo' => (
    'is'      => 'ro',
    'isa'     => 'Pakket::Repository::Spec',
    'lazy'    => 1,
    'default' => sub {
        my $self = shift;

        return Pakket::Repository::Spec->new(
            'backend' => $self->spec_repo_backend,
        );
    },
);

has 'spec_repo_backend' => (
    'is'      => 'ro',
    'isa'     => 'PakketRepositoryBackend',
    'lazy'    => 1,
    'coerce'  => 1,
    'default' => sub {
        my $self = shift;
        return $self->config->{'repositories'}{'spec'};
    },
);

sub is_package_in_spec_repo {
    my ($self, $package) = @_;

    my @versions = map { $_ =~ Pakket::Constants::PAKKET_PACKAGE_SPEC(); "$3:$4" }
        @{ $self->spec_repo->all_object_ids_by_name($package->name, 'perl') };

    return 0 unless @versions; # there are no packages

    if ($self->versioner->is_satisfying($package->version.':'.$package->release, @versions)) {
        $log->debugf("Skipping %s, already have satisfying version: %s", $package->full_name, join(", ", @versions));
        return 1;
    }

    return 0; # spec has package, but version is not compatible
}

sub add_spec_for_package {
    my ($self, $package) = @_;

    if ($self->spec_repo->has_object($package->id) and !$self->overwrite) {
        $log->debugf("Package %s already exists in spec repo (skipping)", $package->full_name);
        return;
    }

    $log->debugf("Creating spec for %s", $package->full_name);

    # we had PackageQuery in $package now convert it to Package
    my $final_package = Pakket::Package->new(%{$self->package});
    $self->spec_repo->store_package_spec($final_package);
}

no Moose::Role;

1;

__END__

=pod

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head2 spec_repo

Stores the spec repository, built with the backend using
C<spec_repo_backend>.

=head2 spec_repo_backend

A hashref of backend information populated from the config file.

=head1 SEE ALSO

=over 4

=item * L<Pakket::Repository::Spec>

=back

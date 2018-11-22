package Pakket::Role::HasSourceRepo;
# ABSTRACT: Provide source repo support

use Moose::Role;
use Pakket::Repository::Source;
use Log::Any              qw< $log >;

has 'source_repo' => (
    'is'      => 'ro',
    'isa'     => 'Pakket::Repository::Source',
    'lazy'    => 1,
    'default' => sub {
        my $self = shift;

        return Pakket::Repository::Source->new(
            'backend' => $self->source_repo_backend,
        );
    },
);

has 'source_repo_backend' => (
    'is'      => 'ro',
    'isa'     => 'PakketRepositoryBackend',
    'lazy'    => 1,
    'coerce'  => 1,
    'default' => sub {
        my $self = shift;
        return $self->config->{'repositories'}{'source'};
    },
);

sub add_source_for_package {
    my ($self, $package, $sources) = @_;

    # check if we already have the source in the repo
    if ($self->source_repo->has_object($package->id) and !$self->overwrite) {
        $log->debugf("Package %s already exists in source repo (skipping)", $package->full_name);
        return;
    }

    #remove .git dir if it exists in sources
    $sources->child('.git')->remove_tree;

    $self->_upload_sources($package, $sources);
}

no Moose::Role;

1;

__END__

=pod

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head2 source_repo

Stores the source repository, built with the backend using
C<source_repo_backend>.

=head2 source_repo_backend

A hashref of backend information populated from the config file.

=head1 SEE ALSO

=over 4

=item * L<Pakket::Repository::Source>

=back

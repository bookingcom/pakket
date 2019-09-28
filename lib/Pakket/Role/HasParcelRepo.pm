package Pakket::Role::HasParcelRepo;
# ABSTRACT: Provide parcel repo support

use v5.22;
use Moose::Role;
use Pakket::Repository::Parcel;

has 'parcel_repo' => (
    'is'      => 'ro',
    'isa'     => 'Pakket::Repository::Parcel',
    'lazy'    => 1,
    'clearer' => '_reset_parcel_repo',
    'default' => sub {
        my $self = shift;

        return Pakket::Repository::Parcel->new(
            'backend' => $self->parcel_repo_backend,
        );
    },
);

has 'parcel_repo_backend' => (
    'is'      => 'ro',
    'isa'     => 'PakketRepositoryBackend',
    'lazy'    => 1,
    'coerce'  => 1,
    'clearer' => '_reset_parcel_repo_backend',
    'default' => sub {
        my $self = shift;
        return $self->config->{'repositories'}{'parcel'};
    },
);

sub reset_parcel_backend {
    my ($self) = @_;

    $self->_reset_parcel_repo_backend();
    $self->_reset_parcel_repo();

    return;
}

no Moose::Role;

1;

__END__

=pod

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head2 parcel_repo

Stores the parcel repository, built with the backend using
C<parcel_repo_backend>.

=head2 parcel_repo_backend

A hashref of backend information populated from the config file.

=head1 SEE ALSO

=over 4

=item * L<Pakket::Repository::Parcel>

=back

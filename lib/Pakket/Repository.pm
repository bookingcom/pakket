package Pakket::Repository;
# ABSTRACT: Build in-memory representation of repo

use Moose;
use MooseX::StrictConstructor;

use Log::Any qw< $log >;
use Pakket::Types qw< PakketRepositoryBackend >;
use Pakket::Utils qw< canonical_package_name >;

has 'backend' => (
    'is'       => 'ro',
    'does'     => 'PakketRepositoryBackend',
    'coerce'   => 1,
    'required' => 1,
);

has 'repo_index' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'builder' => '_build_repo_index',
);

has 'packages_list' => (
    'is'      => 'ro',
    'isa'     => 'ArrayRef',
    'lazy'    => 1,
    'builder' => '_build_packages_list',
);

sub _build_repo_index {
    my $self = shift;
    return $self->backend->create_index;
}

sub _build_packages_list {
    my $self  = shift;
    my $index = $self->repo_index;
    my @packages;

    for my $category ( keys %{$index} ) {
        for my $package ( keys %{ $index->{$category} } ) {
            for my $version (
                keys %{ $index->{$category}{$package}{'versions'} } )
            {
                push @packages,
                    canonical_package_name( $category, $package, $version, );
            }
        }
    }

    return \@packages;
}

sub latest_version {
    my ( $self, $category, $package ) = @_;

    my $repo_index = $self->repo_index;

    $repo_index->{$category}           or return;
    $repo_index->{$category}{$package} or return;

    return $repo_index->{$category}{$package}{'latest'};
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

__END__

=pod

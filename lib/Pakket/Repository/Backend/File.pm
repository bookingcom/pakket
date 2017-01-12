package Pakket::Repository::Backend::File;
# ABSTRACT: A file-based backend repository

use Moose;
use MooseX::StrictConstructor;

use JSON::MaybeXS             qw< decode_json >;
use Path::Tiny                qw< path >;
use Log::Any                  qw< $log >;
use Types::Path::Tiny         qw< Path >;
use Pakket::Utils             qw< canonical_package_name >;

with qw< Pakket::Role::Repository::Backend >;

has 'filename' => (
    'is'       => 'ro',
    'isa'      => Path,
    'coerce'   => 1,
    'required' => 1,
);

has 'repo_index' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'builder' => '_build_repo_index',
);

has '_cached_packages_list' => (
    'is'      => 'ro',
    'isa'     => 'ArrayRef',
    'lazy'    => 1,
    'builder' => '_build_packages_list',
);

sub _build_repo_index {
    my $self     = shift;
    my $filename = $self->filename;
    my $file     = path($filename);

    if ( !$file->is_file ) {
        $log->critical("File '$file' does not exist or cannot be read");
        exit 1;
    }

    return decode_json( $file->slurp_utf8 );
}

sub _build_cached_packages_list {
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

sub packages_list { $_[0]->_cached_packages_list }

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

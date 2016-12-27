package Pakket::Repository;
# ABSTRACT: Build in-memory representation of repo

use Exporter                  qw< import >;
use JSON::MaybeXS             qw< decode_json >;
use Path::Tiny                qw< path >;
use Log::Any                  qw< $log >;
use Moose;
use MooseX::StrictConstructor;
use Types::Path::Tiny         qw< Path >;

use Pakket::ConfigReader;

our @EXPORT_OK = qw< all_packages_in_index_file >;

has 'config_dir' => (
    'is'      => 'ro',
    'isa'     => Path,
    'coerce'  => 1,
    'default' => sub { Path::Tiny->cwd },
);

has 'index_file' => (
    'is'       => 'ro',
    'isa'      => Path,
    'coerce'   => 1,
    'required' => 1,
);

has 'repo' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'lazy'    => 1,
    'builder' => '_build_repo',
);

# This is where my Moose ignorance shows...
# I want to cache this value, but why does it have to be an attribute?
#
# Also, I tried setting isa to Array, but it would fail because it
# considered the builder was not returning an Array, but the scalar
# value (its size).
has 'packages_in_index' => (
    'is'      => 'ro',
    'isa'     => 'ArrayRef',
    'lazy'    => 1,
    'builder' => '_build_packages_in_index',
);

sub latest_version_for {
    my ($self, $category, $package) = @_;

    return '' unless defined $self->repo &&
                     defined $self->repo->{$category} &&
                     defined $self->repo->{$category}{$package} &&
                     defined $self->repo->{$category}{$package}{'latest'};
    return $self->repo->{$category}{$package}{'latest'};
}

# This is ugly and leaks, but we still have some places were
# we want to treat an isolated JSON file as an "index", so we
# export this function here; in truth, this should be private
# to this module (or non-existent).
sub all_packages_in_index_file {
    my ( $index_file ) = @_;

    my $index = decode_json( path($index_file)->slurp_utf8 ) // {};
    return _all_packages_in_index_hash($index);
}

sub _all_packages_in_index_hash {
    my ( $index ) = @_;

    my @packages;
    for my $category ( keys %{$index} ) {
        for my $package ( keys %{ $index->{$category} } ) {
            for my $version ( keys %{ $index->{$category}{$package}{'versions'} } ) {
                push @packages,
                     _make_canonical_package_name($category, $package, $version);
            }
        }
    }
    return @packages;
}

sub _build_packages_in_index {
    my $self = shift;

    my @packages = _all_packages_in_index_hash($self->repo);
    return \@packages;
}

sub _make_canonical_package_name {
    my ($category, $package, $version) = @_;

    return sprintf("%s/%s=%s", $category, $package, $version);
}

sub _build_repo {
    my $self = shift;

    my $data = decode_json($self->index_file->slurp_utf8());
    foreach my $category (keys %$data) {
        foreach my $package_name (keys %{ $data->{$category} }) {
            my $latest = $data->{$category}{$package_name}{'latest'};
            my %versions;
            foreach my $package_version (keys %{ $data->{$category}{$package_name}{'versions'} }) {
                my $directory = $data->{$category}{$package_name}{'versions'}{$package_version};
                $versions{$package_version}{'source'} = $directory;
                my $config = $self->_read_package_config( $category, $package_name, $package_version);
                @{$versions{$package_version}}{keys %$config} = values %$config;
            }
            $data->{$category}{$package_name}{'versions'} = \%versions;
        }
    }

    return $data;
}

sub _read_package_config {
    my ( $self, $category, $package_name, $package_version ) = @_;

    # FIXME: the config class should have "mandatory" fields, add checks

    # read the configuration
    my $config_file = path( $self->config_dir, $category, $package_name,
        "$package_version.toml" );

    if ( !$config_file->exists ) {
        $log->critical("Could not find package config file: $config_file");
        exit 1;
    }

    if ( !$config_file->is_file ) {
        $log->critical("odd config file: $config_file");
        exit 1;
    }

    my $config_reader = Pakket::ConfigReader->new(
        'type' => 'TOML',
        'args' => [ 'filename' => $config_file ],
    );

    my $config = $config_reader->read_config;

    # double check we have the right package configuration
    my $config_name = $config->{'Package'}{'name'};
    if ( !$config_name ) {
        $log->error("Package config must provide 'name'");
        return;
    }

    my $config_category = $config->{'Package'}{'category'};
    if ( !$config_category ) {
        $log->error("Package config must provide 'category'");
        return;
    }

    my $config_version = $config->{'Package'}{'version'};
    if ( !defined $config_version ) {
        $log->error("Package config must provide 'version'");
        return;
    }

    if ( $config_name ne $package_name ) {
        $log->error("Mismatch package names ($package_name / $config_name)");
        return;
    }

    if ( $config_category ne $category ) {
        $log->error(
            "Mismatch package categories ($category / $config_category)");
        return;
    }

    if ( $config_version ne $package_version ) {
        $log->error(
            "Mismatch package versions ($package_version / $config_version)");
        return;

    }

    my @keys_wanted = qw/Prereqs/;
    my %answer;
    @answer{@keys_wanted} = @{$config}{@keys_wanted};
    return \%answer;
}

__PACKAGE__->meta->make_immutable;

no Moose;

1;

__END__

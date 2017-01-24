package Pakket::Repository::Config;
# ABSTRACT: A configuration repository

use Moose;
use MooseX::StrictConstructor;
use Types::Path::Tiny qw< Path >;
use Carp              qw< croak >;
use TOML              qw< to_toml >;
use TOML::Parser;

extends qw< Pakket::Repository >;
with    qw< Pakket::Role::HasDirectory >;

sub _build_backend {
    my $self = shift;

    return [
        'File',
        'directory'      => $self->directory,
        'file_extension' => 'ini',
    ];
}

sub retrieve_package_config {
    my ( $self, $package ) = @_;

    my $config_str = $self->retrieve_content(
        $package->full_name,
    );

    my $config;
    eval {
        $config = TOML::Parser->new( 'strict_mode' => 1 )
                              ->parse($config_str);
        1;
    } or do {
        my $err = $@ || 'Unknown error';
        croak("Cannot read config properly: $err");
    };

	return $config;
}

sub store_package_config {
	my ( $self, $package ) = @_;

    return $self->store_content(
        $package->full_name,
        to_toml( $package->config ),
    );
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
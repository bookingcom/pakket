package Pakket::Repository::Spec;
# ABSTRACT: A spec repository

use Moose;
use MooseX::StrictConstructor;
use Types::Path::Tiny qw< Path >;
use Carp              qw< croak >;
use JSON::MaybeXS     qw< decode_json >;
use Pakket::Utils     qw< encode_json_pretty >;

extends qw< Pakket::Repository >;

sub retrieve_package_spec {
    my ( $self, $package ) = @_;

    my $spec_str = $self->retrieve_content(
        $package->id,
    );

    my $config;
    eval {
        $config = decode_json($spec_str);
        1;
    } or do {
        my $err = $@ || 'Unknown error';
        croak("Cannot read spec properly: $err");
    };

    return $config;
}

sub store_package_spec {
    my ( $self, $package, $spec ) = @_;

    return $self->store_content(
        $package->id,
        encode_json_pretty( $spec || $package->spec ),
    );
}

sub remove_package_spec {
    my ( $self, $package ) = @_;
    return $self->remove_package_file( 'spec', $package );
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

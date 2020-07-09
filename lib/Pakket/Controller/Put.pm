package Pakket::Controller::Put;

# ABSTRACT: Put packages, parcels and specs

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

# core
use experimental qw(declared_refs refaliasing signatures);

# non core
use Module::Runtime qw(use_module);

# local
use Pakket::Type::Package;
use Pakket::Utils qw(normalize_version);

extends qw(Pakket::Controller::BaseRemoteOperation);

has 'file' => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
);

has [qw(overwrite)] => (
    'is'      => 'ro',
    'isa'     => 'Int',
    'default' => 0,
);

sub execute ($self) {
    my $repo = $self->get_repo();

    my ($query) = $self->queries->@*;

    if ($query->category eq 'perl' && $query->is_module()) {
        my $cpan = use_module('Pakket::Helper::Cpan')->new;
        $query->{'name'} = $cpan->determine_distribution($query->name);
        $query->clear_short_name;
    }

    $query->release
        or $self->croak('Release is required');

    my $package;
    if (my @found = $repo->filter_queries([$query])) {
        if ($self->overwrite) {
            $package = $found[0];
        } else {
            $self->croak('Package already exists:', $found[0]->id);
        }
    } else {
        my $version = $query->category eq 'native' ? $query->requirement : normalize_version($query->requirement)
            or $self->croak('Version is required');

        $package = Pakket::Type::Package->new(
            $query->%{qw(category name release)},
            'version' => $version,
        );
    }

    $repo->store_location($package->id, $self->file);

    return 0;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

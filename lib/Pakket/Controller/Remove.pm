package Pakket::Controller::Remove;

# ABSTRACT: Remove packages, parcels and specs

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

# core
use experimental qw(declared_refs refaliasing signatures);

# non core
use Module::Runtime qw(use_module);

# local
use Pakket::Utils qw(normalize_version);

extends qw(Pakket::Controller::BaseRemoteOperation);

sub execute ($self) {
    my $repo = $self->get_repo();

    my \@packages = $self->check_against_repository($repo, $self->_prepare_requirements());
    foreach my $package (@packages) {
        $self->log->notice('Removing object:', $package->id);
        $repo->remove($package->id);
    }

    return 0;
}

sub _prepare_requirements ($self) {
    my $cpan         = use_module('Pakket::Helper::Cpan')->new;
    my $requirements = {
        map {
            if ($_->category eq 'perl' && $_->is_module()) {
                $_->{'name'} = $cpan->determine_distribution($_->name);
                $_->clear_short_name;
            }
            my $version = normalize_version($_->requirement)
                or $self->croak('Version is required');
            $_->release
                or $self->croak('Release is required');

            $_->short_name => $_
        } $self->queries->@*,
    };
    return $requirements;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

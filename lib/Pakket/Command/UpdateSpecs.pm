package Pakket::Command::UpdateSpecs;

# ABSTRACT: Update specs

use v5.22;
use strict;
use warnings;
use namespace::autoclean;

# core
use experimental qw(declared_refs refaliasing signatures);

# noncore
use Log::Any        qw($log);
use Module::Runtime qw(use_module);

# local
use Pakket '-command';

use constant {
    'VALID_REPOS' => {
        'parcel' => 1,
        'source' => 1,
        'spec'   => 1,
    },
};

sub abstract {
    return 'Update specs';
}

sub description {
    return 'Update specs';
}

sub opt_spec ($self, @args) {
    return (                                                                   # no tidy
        undef,
        $self->SUPER::opt_spec(@args),
    );
}

sub validate_args ($self, $opt, $args) {
    $self->SUPER::validate_args($opt, $args);

    $log->debug('pakket', join (' ', @ARGV));

    $args->@*
        and $self->usage_error('Invalid args: ' . join (', ', $args->@*));

    return;
}

sub execute ($self, $opt, $args) {
    my $controller = use_module('Pakket::Controller::UpdateSpecs')->new(
        'config'  => $self->{'config'},
        'repo'    => 'spec',
        'queries' => [],
    );

    return $controller->execute();
}

1;

__END__

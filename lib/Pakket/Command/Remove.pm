package Pakket::Command::Remove;

# ABSTRACT: Remove parcels/sources/specs from the repos

use v5.22;
use strict;
use warnings;
use namespace::autoclean;

# core
use experimental qw(declared_refs refaliasing signatures);

# noncore
use Log::Any qw($log);
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
    return 'Remove parcels/sources/specs from the repos';
}

sub description {
    return 'Remove parcels/sources/specs from the corresponding repos';
}

sub opt_spec ($self, @args) {
    return (                                                                   # no tidy
        ['repo|r=s', 'repo to get object from'],
        ['parcel|p', 'alias of --repo=parcel'],
        ['source|u', 'alias of --repo=source'],
        ['spec|s',   'alias of --repo=spec'],
        undef,
        $self->SUPER::opt_spec(@args),
    );
}

sub validate_args ($self, $opt, $args) {
    $self->SUPER::validate_args($opt, $args);

    $log->debug('pakket', join (' ', @ARGV));

    $args->@*
        or $self->usage_error('Invalid args: ' . join (', ', $args->@*));

    $self->{'repo'}
        ||= $opt->{'repo'}
        || ($opt->{'parcel'} && 'parcel')
        || ($opt->{'spec'}   && 'spec')
        || ($opt->{'source'} && 'source')
        || 'parcel';

    exists VALID_REPOS()->{$self->{'repo'}}
        or $self->usage_error(
        'Invalid repo ' . $self->{'repo'} . ', should be one of: ' . join (', ', keys VALID_REPOS()->%*));

    return;
}

sub execute ($self, $opt, $args) {
    my \@queries = $self->build_queries($self->parse_requested_ids($opt, $args));

    $log->trace('requested packages:', scalar @queries);

    my $controller = use_module('Pakket::Controller::Remove')->new(
        'config'  => $self->{'config'},
        'repo'    => $self->{'repo'},
        'queries' => \@queries,
    );

    return $controller->execute();
}

1;

__END__

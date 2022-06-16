package Pakket::Command::Get;

# ABSTRACT: Get parcels/sources/specs from the repos

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
    return 'Get parcels/sources/specs from the repos';
}

sub description {
    return 'Get parcels/sources/specs from the corresponding repos';
}

sub opt_spec ($self, @args) {
    return (                                                                   # no tidy
        ['repo|r=s',   'repo to get object from (spec is by default)'],
        ['parcel|p',   'alias of --repo=parcel'],
        ['source|s',   'alias of --repo=source'],
        ['spec|j',     'alias of --repo=spec'],
        ['file|f=s',   'path to save file'],
        ['output|o=s', 'output format (for non binary)'],
        undef,
        $self->SUPER::opt_spec(@args),
    );
}

sub validate_args ($self, $opt, $args) {
    $self->SUPER::validate_args($opt, $args);

    $log->debug('pakket', join (' ', @ARGV));

    $args->@* == 1
        or $self->usage_error('Invalid args: ' . join (', ', $args->@*));

    $self->{'repo'}
        ||= $opt->{'repo'}
        || ($opt->{'parcel'} && 'parcel')
        || ($opt->{'spec'}   && 'spec')
        || ($opt->{'source'} && 'source')
        || 'spec';

    exists VALID_REPOS()->{$self->{'repo'}}
        or $self->usage_error(
        'Invalid repo ' . $self->{'repo'} . ', should be one of: ' . join (', ', keys VALID_REPOS()->%*));

    return;
}

sub execute ($self, $opt, $args) {
    my \@queries = $self->build_queries($args);

    $log->trace('requested packages:', scalar @queries);

    my $controller = use_module('Pakket::Controller::Get')->new(
        'config' => $self->{'config'},
        'repo'   => $self->{'repo'},
        'file'   => $opt->{'file'},
        ('output' => $opt->{'output'}) x !!$opt->{'output'},
        'queries' => \@queries,
    );

    return $controller->execute();
}

1;

__END__

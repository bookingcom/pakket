package Pakket::Command::List;

# ABSTRACT: List packages in local/remote repository

use v5.22;
use strict;
use warnings;
use namespace::autoclean;

# core
use Carp;
use experimental qw(declared_refs refaliasing signatures);

# noncore
use Log::Any qw($log);
use Module::Runtime qw(use_module);

# local
use Pakket '-command';

use constant {
    'SUBJECTS' => {
        'absent' => {
            'match'   => '^ab',
            'repo'    => 'spec',
            'handler' => sub ($s) {
                $s->absent();
            },
        },
        'installed' => {
            'match'   => '^in',
            'handler' => sub ($s) {
                $s->installed();
            },
        },
        'parcels' => {
            'match'   => '^pa',
            'repo'    => 'parcel',
            'handler' => sub ($s) {
                $s->parcels();
            },
        },
        'sources' => {
            'match'   => '^so',
            'repo'    => 'source',
            'handler' => sub ($s) {
                $s->sources();
            },
        },
        'specs' => {
            'match'   => '^sp',
            'repo'    => 'spec',
            'handler' => sub ($s) {
                $s->specs();
            },
        },
    },
};

sub abstract {
    return 'List packages/parcels/sources/specs';
}

sub usage_desc ($self, @) {
    return $self->SUPER::usage_desc() . ' ' . join ('|', keys SUBJECTS()->%*);
}

sub description {
    return 'List installed packages, parcels/sources/specs available in the repos';
}

sub opt_spec ($self, @args) {
    return (                                                                   # no tidy
        ['repo|r=s', 'Repository'],
        undef,
        $self->SUPER::opt_spec(@args),
    );
}

sub validate_args ($self, $opt, $args) {
    $self->SUPER::validate_args($opt, $args);

    $log->debug('pakket ' . join (' ', @ARGV));

    my $arg     = $args->[0];
    my $subject = $self->_grep_subject($arg)
        or $self->usage_error(
        "Unknown subject: '$arg'\nPlease provide one of the valid subjects: " . join ('|', keys SUBJECTS()->%*) . "\n");

    $opt->{'repo'} && $subject->{'repo'}
        and $opt->config->{'repositories'}{$subject->{'repo'}} = $opt->{'repo'};

    return;
}

sub execute ($self, $opt, $args) {
    my $subject = $self->_grep_subject($args->[0]);
    my $list    = use_module('Pakket::Controller::List')->new(
        'config'     => $self->{'config'},
        'pakket_dir' => $self->{'config'}{'install_dir'},
    );

    return $subject->{'handler'}->($list);
}

sub _grep_subject ($self, $arg) {
    $arg //= 'parcels';

    my \%map = SUBJECTS();
    foreach my $name (keys %map) {
        $arg =~ $map{$name}{'match'}
            and return $map{$name};
    }

    return;
}

1;

__END__

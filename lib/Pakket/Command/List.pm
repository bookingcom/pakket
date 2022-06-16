package Pakket::Command::List;

# ABSTRACT: List packages in local/remote repository

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
    'SUBJECTS' => {
        'absent' => {
            'match'   => '^ab',
            'repo'    => 'parcel',
            'handler' => sub ($s) {
                $s->absent();
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

        'installed' => {
            'match'   => '^in',
            'handler' => sub ($s) {
                $s->installed();
            },
        },
        'cpan-updates' => {
            'match'   => '^cp',
            'handler' => sub ($s) {
                $s->cpan_updates();
            },
        },
        'updates' => {
            'match'   => '^up',
            'handler' => sub ($s) {
                $s->updates();
            },
        },
    },
};

sub abstract {
    return 'List packages/parcels/sources/specs';
}

sub usage_desc ($self, @) {
    return $self->SUPER::usage_desc() . ' [' . join ('|', sort keys SUBJECTS()->%*) . ']';
}

sub description {
    my $message = <<~"END_HEREDOC";
    List installed packages, parcels/sources/specs available in the repos and absent parcels

            absent               List all packages where not all parcels are built
            installed            List all installed packages
            parcels              List all parcels
            sources              List all sources
            specs                List all specs
            cpan-updates         List all packages which have updated version on METACPAN
            updates              List all packages which have a newer version in a parcel repo
    END_HEREDOC

    return $message;
}

sub opt_spec ($self, @args) {
    return (                                                                   # no tidy
        ['repo|r=s', 'Repository'],
        ['json',     'Format as JSON'],
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
        'json'       => $opt->{'json'},
    );

    return $subject->{'handler'}->($list);
}

sub _grep_subject ($self, $arg) {
    $arg //= 'installed';

    my \%map = SUBJECTS();
    foreach my $name (keys %map) {
        $arg =~ $map{$name}{'match'}
            and return $map{$name};
    }

    return;
}

1;

__END__

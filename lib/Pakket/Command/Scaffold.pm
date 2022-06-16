package Pakket::Command::Scaffold;

# ABSTRACT: Scaffold package source and spec to the repositories

use v5.22;
use strict;
use warnings;
use namespace::autoclean;

# core
use experimental qw(declared_refs refaliasing signatures switch);

# non core
use Log::Any        qw($log);
use Module::Runtime qw(use_module);
use Path::Tiny;

# local
use Pakket '-command';

sub abstract {
    return 'Scaffold package source and spec to the repositories';
}

sub description {
    return 'Scaffold package source and spec to the repositories';
}

sub opt_spec ($self, @args) {
    return (
        ['file|f=s',     'path to input file (- for STDIN)'],
        ['type|t=s',     'type of the input file [cpan, cpanfile, archive, meta]', {'default' => 'cpan'}],
        ['overwrite|w+', 'overwrite artifacts even if they are already exist (overwrite even prereqs if doubled)'],
        ['no-prereqs',   'do not process any dependencies at all'],
        ['keep|k',       'do not delete the build directory'],
        undef,
        ['no-continue|e', 'do not continue on error'],
        ['dry-run|d',     'do not write result into repo'],
        undef,
        ['cpan-02packages=s', '02packages file (optional)'],
        undef,
        ['with-develop',    'process dependencies for develop phase'],
        ['with-recommends', 'process recommended dependencies'],
        ['with-suggests',   'process suggested dependencies'],
        undef,
        $self->SUPER::opt_spec(@args),
    );
}

sub validate_args ($self, $opt, $args) {
    $self->SUPER::validate_args($opt, $args);

    $log->debug('pakket', join (' ', @ARGV));

    given ($opt->{'type'}) {
        when ('archive') {
            $self->validate_provided_file($opt);
            $self->validate_only_one_arg($args);
        }
        when ('meta') {
            $self->validate_provided_file($opt);
            $self->validate_no_args_with_type($opt, $args);
        }
        when (['cpan', undef]) {
            $opt->{'file'}
                ? $self->validate_only_one_arg($args)
                : $self->validate_at_least_one_arg($args);
        }
        when ('cpanfile') {
            $self->validate_provided_file($opt);
            $self->validate_no_args_with_type($opt, $args);
        }
        default {
            $self->usage_error('Invalid --type: ' . $opt->{'type'});
        }
    }

    $self->_determine_queries($opt, $args);
    @{$self->{'queries'} // []}
        and $log->trace('queries: ' . join (', ', map {$_->id} $self->{'queries'}->@*));

    return;
}

sub execute ($self, $opt, $args) {
    my @phases = (qw(configure runtime build test), map {$opt->{"with_$_"} ? $_ : ()} qw(develop));
    my @types  = (qw(requires),                     map {$opt->{"with_$_"} ? $_ : ()} qw(recommends suggests));

    my $controller = use_module('Pakket::Controller::Scaffold')->new(
        'config' => $self->{'config'},
        'phases' => [@phases],
        'types'  => [@types],
        map {defined $opt->{$_} ? +($_ => $opt->{$_}) : +()} qw(dry_run keep no_continue no_prereqs overwrite prefix),
        qw(cpan_02packages),
    );

    return $controller->execute($self->%{qw(queries prereqs)});
}

sub _determine_queries ($self, $opt, $args) {
    my $query;
    my $pq = use_module('Pakket::Type::PackageQuery');
    given ($opt->{'type'}) {
        when ('archive') {
            $query = $pq->new_from_string(
                $args->[0],
                'default_category' => $self->{'config'}->{'default_category'},
                'source'           => $opt->{'file'},
            );
        }
        when ('meta') {
            $query = $pq->new_from_pakket_metafile(path($opt->{'file'}));
        }
        when (['cpan', 'cpanfile', undef]) {
            my @ids = sort $self->parse_requested_ids($opt, $args)->@*;
            $self->build_queries(\@ids);
            return;
        }
    }
    $self->{'queries'} = [$query];

    return;
}

1;

__END__

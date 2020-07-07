package Pakket::Command::Build;

# ABSTRACT: Build a parcel

use v5.22;
use strict;
use warnings;
use namespace::autoclean;

# core
use experimental qw(declared_refs refaliasing signatures);

# non core
use Log::Any qw($log);
use Module::Runtime qw(use_module);
use Path::Tiny;

# local
use Pakket '-command';
use Pakket::Utils::Repository qw(gen_repo_config);

sub abstract {
    return 'Build parcels';
}

sub description {
    return 'Build parcels from prepared source and spec files';
}

sub opt_spec ($self, @args) {
    return (
        ['file|f=s',     'path to input file (- for STDIN)'],
        ['overwrite|w+', 'overwrite artifacts even if they are already exist (overwrite even prereqs if doubled)'],
        ['no-prereqs',   'do not process any dependencies at all'],
        ['keep|k',       'do not delete the build directory'],
        undef,
        ['no-continue|e', 'do not continue on error'],
        ['dry-run|d',     'do not write result into repo'],
        undef,
        ['no-man',     'remove man pages'],
        ['no-test|n+', 'ignore (-n) or skip (-nn) test completely'],
        ['prefix|p=s', 'custom prefix used during build'],
        undef,
        ['source-dir=s', 'directory holding the sources'],
        ['spec-dir=s',   'directory holding the specs'],
        ['output-dir=s', 'output directory'],
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

    my \%config = $self->{'config'};

    # setup default repos
    my %repo_opt = (
        'spec'   => 'spec_dir',
        'source' => 'source_dir',
        'parcel' => 'output_dir',
    );

    foreach my $type (keys %repo_opt) {
        my $opt_key   = $repo_opt{$type};
        my $directory = $opt->{$opt_key};
        if ($directory) {
            my $repo_conf = gen_repo_config($type, $directory);
            $config{'repositories'}{$type} = $repo_conf;
        }
        $config{'repositories'}{$type}
            or $self->usage_error("Missing configuration for $type repository");
    }

    $opt->{'build_dir'}
        and path($opt->{'build_dir'})->is_dir
        || $self->usage_error($log->critical('You asked to use a build dir that does not exist:', $opt->{'build_dir'}));

    $opt->{'file'}
        ? $self->validate_no_args($args)
        : $self->validate_at_least_one_arg($args);
    $self->build_queries($self->parse_requested_ids($opt, $args));

    return;
}

sub execute ($self, $opt, $args) {
    my @phases = (qw(configure runtime build test), map {$opt->{"with_$_"} ? $_ : ()} qw(develop));
    my @types  = (qw(requires),                     map {$opt->{"with_$_"} ? $_ : ()} qw(recommends suggests));

    my $controller = use_module('Pakket::Controller::Build')->new(
        'config' => $self->{'config'},
        'phases' => [@phases],
        'types'  => [@types],
        map {defined $opt->{$_} ? +($_ => $opt->{$_}) : +()} qw(dry_run keep no_continue no_prereqs overwrite prefix),
        qw(no_man no_test prefix),
    );

    return $controller->execute($self->%{qw(queries prereqs)});
}

1;

__END__

=pod

=head1 SYNOPSIS

    $ pakket build perl/Dancer2

    $ pakket build native/tidyp=1.04

=head1 DESCRIPTION

Once you have your configurations (spec) and the sources for your
packages, you can issue a build of them using this command. It will
generate parcels, which are the build artifacts.

(The parcels are equivalent of C<.rpm> or C<.deb> files.)

    # Build latest version of package "Dancer2" of category "perl"
    $ pakket build perl/Dancer2

    # Build specific version
    $ pakket build perl/Dancer2=0.205000

Depending on the configuration you have for Pakket, the result will
either be saved in a file or in a database or sent to a remote server.

=cut

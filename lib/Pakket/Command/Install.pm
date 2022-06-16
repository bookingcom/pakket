package Pakket::Command::Install;

# ABSTRACT: Install a Pakket package

use v5.22;
use strict;
use warnings;
use open ':std', ':encoding(UTF-8)';
use namespace::autoclean;

# core
use Digest::SHA  qw(sha1_hex);
use experimental qw(declared_refs refaliasing signatures);

# noncore
use Log::Any        qw($log);
use Module::Runtime qw(use_module);
use Path::Tiny;

# local
use Pakket '-command';

use constant {                                                                 # no tidy
    'MIN_MODULES_TO_ROLLBACK' => 30,
};

sub abstract {
    return 'Install packages';
}

sub description {
    return 'Install packages';
}

sub opt_spec ($self, @args) {
    return (
        ['file|input-file|f=s', 'process everything listed in this file'],
        ['overwrite|force|w+',  'force reinstall if already installed'],
        ['no-prereqs',          'do not process any dependencies at all'],
        ['continue',            'continue on errors'],
        [
            'dry-run|d+',
            'dry-run installation and return only list of packages to be installed (can be set twice to enforce recursive check for dependencies)',
        ],
        undef,
        ['jobs|j=i', 'number of workers to run in parallel'],
        ['atomic!',  'operation on current library is atomic'],
        undef,
        ['from=s', 'directory to install the packages from'],
        ['to=s',   'directory to install the package in'],
        undef,
        ['show-installed', 'print list of installed packages (backward compatibility)'],
        undef,
        ['with-build',      'process dependencies for build phase'],
        ['with-configure',  'process dependencies for configure phase'],
        ['with-develop',    'process dependencies for develop phase'],
        ['with-test',       'process dependencies for test phase'],
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

    defined $opt->{'from'}
        and $config{'repositories'}{'parcel'} = $opt->{'from'};
    $config{'repositories'}{'parcel'}
        or $self->usage_error("Missing option where to install from\n(Create a configuration or use --from)");

    defined $opt->{'to'}
        and $config{'install_dir'} = $opt->{'to'};
    $config{'install_dir'}
        or $self->usage_error("Missing option where to install\n(Create a configuration or use --to)");

    $config{'jobs'}   = $opt->{'jobs'}   // $config{'jobs'}   // 1;
    $config{'atomic'} = $opt->{'atomic'} // $config{'atomic'} // 1;

    if ($opt->{'show_installed'}) {
        $self->validate_no_args($args);
    } else {
        $opt->{'file'}
            ? $self->validate_no_args($args)
            : $self->validate_at_least_one_arg($args);
        $self->_determine_queries($opt, $args);
    }
    return;
}

sub execute ($self, $opt, $args) {
    my \%config = $self->{'config'};

    $opt->{'show_installed'} and return use_module('Pakket::Controller::List')->new(
        'pakket_dir' => $config{'install_dir'},
    )->installed();

    my @phases = (qw(runtime),  map {$opt->{"with_$_"} ? $_ : ()} qw(build configure develop test));
    my @types  = (qw(requires), map {$opt->{"with_$_"} ? $_ : ()} qw(recommends suggests));

    my $controller = use_module('Pakket::Controller::Install')->new(
        'allow_rollback' => $config{'allow_rollback'} // 0,
        'atomic'         => $config{'atomic'},
        'config'         => $self->{'config'},
        'jobs'           => $config{'jobs'},
        'keep_rollbacks' => $config{'keep_rollbacks'} // 1,
        'pakket_dir'     => $config{'install_dir'},
        'rollback_tag'   => $opt->{'rollback_tag'}   // '',
        'use_hardlinks'  => $config{'use_hardlinks'} // 0,
        'phases'         => [@phases],
        'types'          => [@types],
        map {defined $opt->{$_} ? +($_ => $opt->{$_}) : +()} qw(dry_run continue no_prereqs overwrite),
    );

    return $controller->execute($self->%{qw(queries prereqs)});
}

sub _determine_queries ($self, $opt, $args) {
    my @ids = sort $self->parse_requested_ids($opt, $args)->@*;

    if ($self->{'config'}{'allow_rollback'} and MIN_MODULES_TO_ROLLBACK() < @ids) {
        $opt->{'rollback_tag'} = sha1_hex(@ids);
        $log->debugf('rollback_tag %s is generated for requested %d packages', $opt->{'rollback_tag'}, scalar @ids);
    }

    $self->build_queries(\@ids);
    @{$self->{'queries'} // []}
        and $log->trace('queries: ' . join (', ', map {$_->id} $self->{'queries'}->@*));
    return;
}

1;

__END__

=pod

=head1 SYNOPSIS

    # Install the first release of a particular version
    # of the package "Pakket" of the category "perl"

    #$ pakket install perl/Pakket=3.1415:1
    #$ pakket install perl/Pakket=3.1415
    #$ pakket install perl/Pakket

    #$ cat file/pakket.list | pakket install -f -

    #$ pakket install --help

=head1 DESCRIPTION

Installing Pakket packages requires knowing the package names,
including their category, their name, their version, and their release.
If you do not provide a version or release, it will simply take the
last one available.

=cut

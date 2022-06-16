package Pakket::Command::Uninstall;

# ABSTRACT: The pakket uninstall command

use v5.22;
use strict;
use warnings;
use open ':std', ':encoding(UTF-8)';
use namespace::autoclean;

# core
use experimental qw(declared_refs refaliasing signatures);

# noncore
use IO::Prompt::Tiny qw(prompt);
use Log::Any         qw($log);
use Module::Runtime  qw(use_module);
use Path::Tiny;

# local
use Pakket '-command';

sub abstract {
    return 'Uninstall packages';
}

sub description {
    return 'Uninstall packages';
}

sub opt_spec ($self, @args) {
    return (
        ['to=s',                'directory where packages are installed'],
        ['atomic!',             'operation on current library is atomic'],
        ['file|input-file|f=s', 'process everything listed in this file'],
        ['no-prereqs',          'don\'t remove dependencies'],
        ['dry-run',             'dry run uninstall'],
        undef,
        $self->SUPER::opt_spec(@args),
    );
}

sub validate_args ($self, $opt, $args) {
    $self->SUPER::validate_args($opt, $args);

    $log->debug('pakket', join (' ', @ARGV));

    my \%config = $self->{'config'};

    defined $opt->{'to'}
        and $config{'install_dir'} = $opt->{'to'};
    $config{'install_dir'}
        or $self->usage_error("Missing option where to install\n(Create a configuration or use --to)");

    $config{'atomic'} = $opt->{'atomic'} // $config{'atomic'} // 1;

    my @ids = sort $self->parse_requested_ids($opt, $args)->@*;

    $self->build_queries(\@ids);
    @{$self->{'queries'} // []}
        and $log->trace('queries: ' . join (', ', map {$_->id} $self->{'queries'}->@*));

    return;
}

sub execute ($self, $opt, $args) {
    my \%config = $self->{'config'};

    my @phases = (qw(runtime build configure develop test));
    my @types  = (qw(requires recommends suggests));

    my $controller = use_module('Pakket::Controller::Uninstall')->new(
        'atomic'     => $config{'atomic'},
        'config'     => $self->{'config'},
        'pakket_dir' => $config{'install_dir'},
        'phases'     => [@phases],
        'types'      => [@types],
        map {defined $opt->{$_} ? +($_ => $opt->{$_}) : +()} qw(dry_run no_prereqs),
    );

    # my @packages_for_uninstall = $controller->get_list_of_packages_for_uninstall();
    #
    # print "We are going to remove:\n";
    # for my $package (@packages_for_uninstall) {
    # print "* $package->{category}/$package->{name}\n";
    # }
    #
    # my $answer = prompt('Continue?', 'y');
    #
    # lc $answer eq 'y'
    # and $controller->execute($self->%{qw(queries prereqs)});

    return $controller->execute($self->%{qw(queries prereqs)});
}

1;

__END__

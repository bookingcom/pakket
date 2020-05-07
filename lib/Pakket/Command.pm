package Pakket::Command;

# ABSTRACT: Base command provides global options

use v5.22;
use strict;
use warnings;
use namespace::autoclean;

# core
use experimental qw(declared_refs refaliasing signatures switch);

# non core
use App::Cmd::Setup '-command';
use Log::Any::Adapter;
use Log::Any::Adapter::Dispatch;
use Module::CPANfile;
use Module::Runtime qw(use_module);
use Path::Tiny;

sub opt_spec {
    my \%defaults = _global_options_defaults();
    return (
        ['config|c=s', "path to configuration file (default: $defaults{'config'})"],
        ['logfile=s',  "path to log file (default: $defaults{'logfile'})"],
        ['verbose|v+', 'increase output verbosity (can be provided multiple times)'],
    );
}

sub validate_args ($self, $opt, $args) {
    my \%defaults = _global_options_defaults();

    $self->{'config'}  = $self->_read_config($opt);
    $self->{'logfile'} = $opt->{'logfile'} || $self->{'config'}{'log_file'} || $defaults{'logfile'};
    $self->{'verbose'} = $opt->{'verbose'};

    my $plog = use_module('Pakket::Log');
    Log::Any::Adapter->set('Dispatch', 'dispatcher' => $plog->build_logger($self->{'verbose'}, $self->{'logfile'}));

    return;
}

sub parse_requested_ids ($self, $opt, $args) {
    my @ids;
    given ($opt->{'file'}) {
        when (not defined) {
            @ids = $args->@*;
        }
        when ('-') {
            open my $fh, '<&', *STDIN
                or $self->usage_error("Unable to open stdin for reading: $!");
            chomp (@ids = <STDIN>);
            close $fh;
        }
        default {
            my @lines = path($opt->{'file'})->lines_utf8({'chomp' => 1});
            if ($self->_is_cpan_file(\@lines)) {
                $self->_read_cpan_file($opt->{'file'});
            } else {
                @ids = @lines;
            }
        }
    }

    @ids and $ids[0] =~ s{\x{FEFF}}{};                                         # remove bom if it exists
    @ids = grep {!m/^#/} @ids;

    return \@ids;
}

sub build_queries ($self, $ids) {
    my $pq = use_module('Pakket::Type::PackageQuery');

    my @result = map {$pq->new_from_string($_, 'default_category' => $self->{'config'}{'default_category'} // 'perl')}
        $ids->@*;

    $self->{'queries'} = \@result;

    return \@result;
}

sub validate_no_args ($self, $args) {
    $args->@*
        and $self->usage_error('Should not provide any arguments');
    return;
}

sub validate_only_one_arg ($self, $args) {
    $args->@* == 1
        or $self->usage_error('Must provide exactly one package id (category/name=version:release)');
    return;
}

sub validate_at_least_one_arg ($self, $args) {
    $args->@*
        or $self->usage_error('Must provide at least one package id (category/name=version:release)');
    return;
}

sub validate_provided_file ($self, $opt) {
    $opt->{'file'}
        or $self->usage_error('Must provide input file for type: ' . $opt->{'type'});
    return;
}

sub validate_no_args_with_type ($self, $opt, $args) {
    $args->@*
        and $self->usage_error('Should not provide any arguments when using --type=' . $opt->{'type'});
    return;
}

sub _is_cpan_file ($self, $lines) {
    my @matched = grep {m{^ \s* requires\s+.+}xms} $lines->@*;
    return !!@matched;
}

sub _global_options_defaults {
    return {
        'config'  => '~/.config/pakket.json',
        'logfile' => '/var/log/pakket.log',
    };
}

sub _read_config ($self, $opt) {
    my $config_file   = $opt->{'config'};
    my $pconfig       = use_module('Pakket::Config');
    my $config_reader = $pconfig->new($config_file ? ('files' => [$config_file]) : ());

    return $config_reader->read_config;
}

sub _read_cpan_file ($self, $input) {
    my $prereqs = Module::CPANfile->load($input)->prereq_specs;

    $prereqs
        and $self->{'prereqs'} = $prereqs;

    return !!$prereqs;
}

1;

__END__

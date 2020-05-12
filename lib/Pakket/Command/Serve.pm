package Pakket::Command::Serve;

# ABSTRACT: Serve Pakket objects over HTTP

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

sub abstract {
    return 'Serve objects';
}

sub description {
    return 'Serve objects';
}

sub opt_spec ($self, @args) {
    return (                                                                   # no tidy
        ['port=s', 'port where server will listen'],
        undef,
        $self->SUPER::opt_spec(@args),
    );
}

sub validate_args ($self, $opt, $args) {
    $self->SUPER::validate_args($opt, $args);

    $log->debug('pakket', join (' ', @ARGV));

    return;
}

sub execute ($self, $opt, $args) {
    my $server = use_module('Pakket::Web::Server')->new(                       # no tidy
        map {defined $opt->{$_} ? ($_ => $opt->{$_}) : ()} qw(port),
    );

    return $server->run();
}

1;

__END__

=pod

=head1 SYNOPSIS

    $ pakket serve
    $ pakket serve --port 3000

=head1 DESCRIPTION

The C<serve> command allows you to start a web server for Pakket. It is
highly configurable and can serve any amount of repositories of all
kinds.

It will load one of following files in the following order:

=over 4

=item * C<PAKKET_WEB_CONFIG> environment variable (to a filename)

=item * C<~/.config/pakket-web.json>

=item * C</etc/pakket-web.json>

=back

=head2 Configuration example

    $ cat ~/.config/pakket-web.json

    {
        "repositories" : [
            {
                "type" : "spec",
                "path" : "/pakket/spec"
                "backend" : [
                    "http",
                    "host", "pakket.mydomain.com",
                    "port", 80
                ]
            },
            {
                "type" : "source",
                "path" : "/pakket/source",
                "backend" : [
                    "file",
                    "directory", "/mnt/pakket-sources"
                ],
            },

            ...
        ]
    }

=cut

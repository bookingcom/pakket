package Pakket::CLI::Command::serve;
# ABSTRACT: Serve Pakket objects over HTTP

use v5.22;
use strict;
use warnings;

use Path::Tiny      qw< path >;
use Log::Any::Adapter;

use Pakket::CLI '-command';
use Pakket::Web::Server;
use Pakket::Log;

sub abstract    { 'Serve objects' }
sub description { 'Serve objects' }

sub opt_spec {
    return (
        [ 'port=s',     'port where server will listen', ],
        [ 'verbose|v+', 'verbose output (can be provided multiple times)' ],
    );
}

sub validate_args {
    my ( $self, $opt ) = @_;

    Log::Any::Adapter->set( 'Dispatch',
        'dispatcher' => Pakket::Log->build_logger( $opt->{'verbose'} ) );
}

sub execute {
    my ( $self, $opt ) = @_;
    my $server = Pakket::Web::Server->new(
        # default main object
        map( +(
            defined $opt->{$_}
                ? ( $_ => $opt->{$_} )
                : ()
        ), qw< port > ),
    );

    $server->run();
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

=item * C<~/.pakket-web.json>

=item * C</etc/pakket-web.json>

=back

=head2 Configuration example

    $ cat ~/.pakket-web.json

    {
        "repositories" : [
            {
                "type" : "Spec",
                "path" : "/pakket/spec"
                "backend" : [
                    "HTTP",
                    "host", "pakket.mydomain.com",
                    "port", 80
                ]
            },
            {
                "type" : "Source",
                "path" : "/pakket/source",
                "backend" : [
                    "File",
                    "directory", "/mnt/pakket-sources"
                ],
            },

            ...
        ]
    }

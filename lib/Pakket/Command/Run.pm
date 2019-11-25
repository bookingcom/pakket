package Pakket::Command::Run;

# ABSTRACT: The pakket run command

use v5.22;
use strict;
use warnings;

use Pakket '-command';
use Pakket::Runner;
use Pakket::Log;
use Log::Any::Adapter;
use Path::Tiny qw< path >;

sub abstract    {'Run commands using pakket'}
sub description {'Run commands using pakket'}

sub opt_spec {
    return (['from=s', 'defines pakket active directory to use. ' . '(mandatory, unless set in PAKKET_ACTIVE_PATH)']);
}

sub validate_args {
    my ($self, $opt) = @_;

    Log::Any::Adapter->set('Dispatch', 'dispatcher' => Pakket::Log->build_logger($opt->{'verbose'}));

    my $active_path
        = exists $ENV{'PAKKET_ACTIVE_PATH'}
        ? $ENV{'PAKKET_ACTIVE_PATH'}
        : $opt->{'from'};

    $active_path
        or $self->usage_error('No active path provided');

    $opt->{'active_path'} = $active_path;
}

sub execute {
    my ($self, $opt, $args) = @_;

    my $runner = Pakket::Runner->new(
        'active_path' => $opt->{'active_path'},
    );

    exit $runner->run(@{$args});
}

1;

__END__

=pod

=head1 SYNOPSIS

    # Generate environment variables
    $ pakket run --from=/opt/pakket/

    # Run application directly
    $ pakekt run --from=/opt/pakket myscript.pl

=head1 DESCRIPTION

The runner allows you to either run your application in Pakket or set
up environment variables so you could run your application later, not
requiring the runner again.

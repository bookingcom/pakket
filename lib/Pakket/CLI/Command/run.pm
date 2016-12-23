package Pakket::CLI::Command::run;
# ABSTRACT: The pakket run command

use strict;
use warnings;
use Pakket::CLI '-command';
use Pakket::Runner;
use Pakket::Log;
use Log::Any::Adapter;
use Path::Tiny      qw< path >;

sub abstract    { 'Run commands using pakket' }
sub description { 'Run commands using pakket' }

sub opt_spec {
    return (
        [
            'from=s',
            'defines pakket active directory to use. (mandatory, unless set in PAKKET_ACTIVE_PATH)',
            { 'required' => 1 },
        ],
    );
}

sub validate_args {
    my ( $self, $opt, $args ) = @_;

    Log::Any::Adapter->set( 'Dispatch',
        'dispatcher' => Pakket::Log->build_logger( $opt->{'verbose'} ) );

    my $active_path
        = exists $ENV{'PAKKET_ACTIVE_PATH'}
        ? $ENV{'PAKKET_ACTIVE_PATH'}
        : $self->{'runner'}{'active_path'};

    $active_path
        or $self->usage_error('No active path provided');

    $self->{'runner'}{'args'}        = $args;
    $self->{'runner'}{'active_path'} = $active_path;
}

sub execute {
    my $self = shift;

    my $runner = Pakket::Runner->new(
        'active_path' => $self->{'runner'}{'active_path'},
    );

    exit $runner->run( @{ $self->{'runner'}{'args'} } );
}

1;

__END__

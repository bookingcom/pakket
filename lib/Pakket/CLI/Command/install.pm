package Pakket::CLI::Command::install;
# ABSTRACT: The pakket install command

use strict;
use warnings;
use Pakket::CLI '-command';
use Pakket::Installer;
use Pakket::Log;
use Log::Any::Adapter;
use Path::Tiny      qw< path >;

sub abstract    { 'Install a package' }
sub description { 'Install a package' }

sub opt_spec {
    return (
        [ 'to=s',       'directory to install the package in'  ],
        [ 'verbose|v+', 'verbose output (can be provided multiple times)' ],
    );
}

sub validate_args {
    my ( $self, $opt, $args ) = @_;

    defined $opt->{'to'}
        and $self->{'installer'}{'repo_dir'} = $opt->{'to'};

    @{$args} == 0
        and $self->usage_error('Must provide package to install');

    my $package = $args->[0];

    # FIXME: support more options here :)
    # (validation for URLs, at least for now)
    -f $package
        or $self->usage_error('Currently only a bundle file is supported');

    $self->{'bundle_file'} = $package;
}

sub execute {
    my $self      = shift;
    my $installer = Pakket::Installer->new(
        map( +(
            defined $self->{'installer'}{$_}
                ? ( $_ => $self->{'installer'}{$_} )
                : ()
        ), qw< repo_dir > ),
    );

    my $logger = Pakket::Log->cli_logger(1); # verbosity
    Log::Any::Adapter->set( 'Dispatch', dispatcher => $logger );

    $installer->install_file( $self->{'bundle_file'} );
}

1;

__END__

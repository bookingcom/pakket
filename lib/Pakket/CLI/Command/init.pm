package Pakket::CLI::Command::init;

# ABSTRACT: Initialize a pakket instance

use strict;
use warnings;
use English '-no_match_vars';
use Pakket::CLI '-command';
use Pakket::Log;
use Pakket::Utils qw< is_writeable >;
use Log::Any::Adapter;
use Log::Any   qw< $log >;
use Path::Tiny qw< path >;
use File::HomeDir;

sub abstract    {'Initialize Pakket'}
sub description {'Initialize Pakket'}

sub opt_spec {
    return (
        [ 'repo-dir=s', 'repo directory (default: /var/lib/pakket)' ],
        [ 'local',      'short-hand for --repo-dir=~/.pakket' ],
        [ 'force|f',    'force init (for reinitialization)' ],
        [ 'verbose|v+', 'verbose output (can be provided multiple times)' ],
    );
}

sub validate_args {
    my ( $self, $opt, $args ) = @_;

    my $logger = Pakket::Log->cli_logger(2); # verbosity
    Log::Any::Adapter->set( 'Dispatch', dispatcher => $logger );

    # global installation and pakket is already available
    if (  !$opt->{'repo_dir'}
        && $ENV{'PAKKET_REPO'}
        && -d $ENV{'PAKKET_REPO'}
        && !$opt->{'force'} )
    {
        $log->critical(
            "Pakket is already globally initialized at $ENV{'PAKKET_REPO'}");
        exit 1;
    }

    $self->{'repo'} = path(
        $opt->{'repo_dir'} // $opt->{'local'}
        ? ( File::HomeDir->my_home, '.pakket' )
        : ( Path::Tiny->rootdir, qw< usr local pakket > ),
    );
}

sub execute {
    my $self = shift;

    # 1. create main repo directory
    # TODO: allow configuration files? interactive?
    my $repo_dir = $self->{'repo'};

    if ( !is_writeable($repo_dir) ) {
        $log->critical("No permissions to write to $repo_dir.");
        exit 1;
    }

    $repo_dir->is_dir
        or $repo_dir->mkpath;

    # 2. print the configuration
    my $pakket_homedir
        = path( File::HomeDir->my_home,
        $OSNAME =~ m{win}ms ? 'pakket' : '.pakket' );

    $pakket_homedir->is_dir
        or $pakket_homedir->mkpath;

    # FIXME: currently only bash support, what about csh/fish/zsh/Windows?
    my $shellfile = path( $pakket_homedir, 'pakket.sh' );
    $shellfile->spew(
        "export PAKKET_REPO=$repo_dir\n",
        "export PERL5LIB=$repo_dir/lib/perl5:\$PERL5LIB\n",
        "export LD_LIBRARY_PATH=$repo_dir/lib:\$LD_LIBRARY_PATH\n",
    );

    $log->info("Done. Please add $shellfile to your bashrc.");
}

1;

__END__

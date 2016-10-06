#!perl

use strict;
use warnings;
use Getopt::Long::Descriptive;
use Log::Any::Adapter;

use Pakket::Log;
use Pakket::Scaffolder::Perl;

sub help {
    my $msg = shift;

    $msg and print "$msg\n";

    print << "_END_HELP";
$0 INPUT

INPUT:
$0 --cpanfile FILE

    cpanfile    provide a cpanfile to read modules from
    config-dir  directory to write the configuration to (TOML file)
    source-dir  directory to write the sources to (downloads if provided)
    json-file   file to generate json configuration to
    extract     extract downloaded source tarball (default=0)

_END_HELP

    exit;
}

my ( $opt, $usage ) = describe_options(
    "$0 %o",
    [ 'config-dir=s', 'directory to write the configuration to (TOML files)', { required => 1 } ],
    [ 'cpanfile=s',   'cpanfile to parse (mandatory unless using module)', {} ],
    [ 'module=s',   'module to build configuration for (mandatory unless using cpanfile)', {} ],
    [ 'source-dir=s', 'directory to write the sources to (downloads if provided)', {} ],
    [ 'json-file=s',  'file to generate json configuration to', {} ],
    [ 'phase=s@',      "additional phases to use ('develop' = author_requires, 'test' = test_requires). configure & runtime are done by default.", {} ],
    [ 'extract',      'extract downloaded source tarball', { default => 0 } ],
    [],
    [ 'help', 'Usage' ],
);

if ( $opt->help or !( $opt->cpanfile xor $opt->module ) ) {
    print $usage->text;
    exit;
}

my $logger = Pakket::Log->cli_logger(2); # verbosity
Log::Any::Adapter->set( 'Dispatch', dispatcher => $logger );

my $sc = Pakket::Scaffolder::Perl->new(
    config_dir => $opt->config_dir,
    json_file  => $opt->json_file,
    source_dir => $opt->source_dir,
    extract    => $opt->extract,
    $opt->cpanfile ? ( cpanfile => $opt->cpanfile ) : (),
    $opt->module   ? ( module   => $opt->module   ) : (),
);

$sc->run;

1;

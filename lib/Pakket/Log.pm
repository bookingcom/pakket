package Pakket::Log;
# ABSTRACT: A logger for Pakket

use strict;
use warnings;
use parent 'Exporter';
use Log::Dispatch;
use Path::Tiny qw< path >;
use Log::Any   qw< $log >;
use Term::GentooFunctions qw< ebegin eend >;

use constant {
    'DEBUG_LOG_LEVEL'    => 3,
    'DEBUG_INFO_LEVEL'   => 2,
    'DEBUG_NOTICE_LEVEL' => 1,

    'TERM_SIZE_MAX'     => 80,
    'TERM_EXTRA_SPACES' => ( length(' * ') + length(' [ ok ]') ),
};

# Just so I remember it:
# 1  fatal     system unusable, aborts program!
# 2  alert     failure in primary system
# 3  critical  failure in backup system
# 4  error     non-urgent program errors, a bug
# 5  warning   possible problem, not necessarily error
# 6  notice    unusual conditions
# 7  info      normal messages, no action required
# 8  debug     debugging messages for development
# 9  trace     copious tracing output

our @EXPORT_OK = qw< log_success log_fail >; ## no critic qw(Modules::ProhibitAutomaticExportation)

sub _extra_spaces {
    my $msg = shift;
    return abs( TERM_SIZE_MAX() - ( length($msg) + TERM_EXTRA_SPACES() ) );
}

sub _log_to_outputs {
    my ( $msg, $status ) = @_;
    my $status_output = $status ? ' [ ok ]' : ' [ !! ]';
    my @log_outputs   = $log->adapter->{'dispatcher'}->outputs;

    foreach my $output (@log_outputs) {
        if ( ref($output) =~ m{^Log::Dispatch::Screen}xms ) {
            ebegin $msg;
            eend 1;
            next;
        }

        my $level   = $status ? 'info' : 'error';
        my $message = " * $msg" . ' ' x _extra_spaces($msg) . $status_output;

        $output->log(
            'level'   => $level,
            'message' => $message,
        );
    }

    return $msg;
}

sub log_success {
    my $msg = shift;
    return _log_to_outputs( $msg, 1 );
}

sub log_fail {
    my $msg = shift;
    return _log_to_outputs( $msg, 0 );
}

sub arg_default_logger {
    return $_[1] || Log::Dispatch->new(
        'outputs' => [
            [
                'Screen',
                'min_level' => 'notice',
                'newline'   => 1,
            ],
        ],
    );
}

sub build_logger {
    my ( $class, $verbose, $file ) = @_;
    my $logger = Log::Dispatch->new(
        'outputs' => [
            $class->_build_logger($file),
            $class->_cli_logger( $verbose // 1 ),
        ],
    );

    return $logger;
}

sub _build_logger {
    my ($class, $file) = @_;

    if (!$file) {
        my $dir = Path::Tiny::path('~/.pakket');
        eval {
            $dir->mkpath;
            1;
        } or do {
            die "Can't create directory $dir : " . $!;
        };

        $file = $dir->child("pakket.log")->stringify;
    }

    return [
        'File',
        'min_level' => 'debug',
        'filename'  => $file,
        'newline'   => 1,
    ];
}

sub cli_logger {
    my ( $class, $verbose ) = @_;

    my $logger = Log::Dispatch->new(
        'outputs' => [ $class->_cli_logger($verbose) ],
    );

    return $logger;
}

sub _cli_logger {
    my ( $class, $verbose ) = @_;

    $verbose ||= 0;

    my $screen_level =
        $verbose >= +DEBUG_LOG_LEVEL    ? 'debug'  : # log 2
        $verbose == +DEBUG_INFO_LEVEL   ? 'info'   : # log 1
        $verbose == +DEBUG_NOTICE_LEVEL ? 'notice' : # log 0
                                          'warning';
    return [
        'Screen::Gentoo',
        'min_level' => $screen_level,
        'newline'   => 1,
        'utf8'      => 1,
    ];
}

1;

__END__

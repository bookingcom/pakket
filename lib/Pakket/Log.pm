package Pakket::Log;
# ABSTRACT: A logger for Pakket

use 5.022;
use strict;
use warnings;
use parent 'Exporter';
use Carp;
use IO::Interactive;
use JSON::MaybeXS         qw< encode_json >;
use Log::Any              qw< $log >;
use Log::Dispatch;
use Path::Tiny            qw< path >;
use Sys::Syslog;
use Term::GentooFunctions qw< ebegin eend >;
use Time::Format          qw< %time >;
use Time::HiRes           qw< gettimeofday >;
use Try::Tiny;

use constant {
    'DEBUG_LOG_LEVEL'  => 3,
    'INFO_LOG_LEVEL'   => 2,
    'NOTICE_LOG_LEVEL' => 1,

    'TERM_SIZE_MAX'     => 80,
    'TERM_EXTRA_SPACES' => ( length(' * ') + length(' [ ok ]') ),
};

# Just so I remember it:
# 1  emergency system unusable, aborts program!
# 2  alert     failure in primary system
# 3  critical  failure in backup system
# 4  error     non-urgent program errors, a bug
# 5  warning   possible problem, not necessarily error
# 6  notice    unusual conditions
# 7  info      normal messages, no action required
# 8  debug     debugging messages for development
# 9  trace     copious tracing output

sub send_data {
    my ($data, $started, $finished) = @_;
    $data && $data->{'severity'} or return;

    $started && $finished and $data->{'took'} = $finished - $started;

    openlog('pakket', 'ndelay,pid');
    syslog($data->{'severity'}, encode_json($data));
    closelog();
}

sub build_logger {
    my ( $class, $verbosity, $file, $force_raw ) = @_;

    my @outputs = (
        $class->_cli_logger($verbosity, $force_raw),
        $class->_syslog_logger(),
    );

    if ($file && -w $file) {
        push(@outputs, $class->_file_logger($file));
    }

    return Log::Dispatch->new(
        'outputs' => \@outputs,
    );
}

sub _cli_logger {
    my ( $class, $verbosity, $force_raw ) = @_;

    return [
        IO::Interactive::is_interactive() && !$force_raw ?  'Screen::Gentoo' : ('Screen', 'stderr' => 0),
        'min_level' => $class->_verbosity_to_loglevel($verbosity),
        'newline'   => 1,
        'utf8'      => 1,
    ];
}

sub _syslog_logger {
    return [
        'Syslog',
        'min_level' => 'warning',
        'ident'     => 'pakket',
        'callbacks' => [ sub {
            my %data = @_;
            return encode_json(\%data);
        } ],
    ];
}

sub _file_logger {
    my ($class, $file) = @_;

    if (!$file) {
        my $dir = Path::Tiny::path('~/.pakket');
        eval {
            $dir->mkpath;
            1;
        } or do {
            croak "Can't create directory $dir : " . $!;
        };

        $file = $dir->child("pakket.log")->stringify;
    }

    return [
        'File',
        'min_level' => 'debug',
        'filename'  => $file,
        'newline'   => 1,
        'mode'      => '>>',
        'callbacks' => [ sub {
            my %data = @_;
            my $localtime = gettimeofday;
            my $timestr = try {
                $time{'yyyy-mm-dd hh:mm:ss.mmm', $localtime};
            } catch {
                $time{'yyyy-mm-dd hh:mm:ss.mmm', int($localtime)};
            };
            return sprintf '[%s] %s: %s', $timestr, $data{'level'}, $data{'message'};
        } ],
    ];
}

sub _verbosity_to_loglevel {
    my ( $class, $verbosity ) = @_;

    $verbosity ||= 0;
    $verbosity += NOTICE_LOG_LEVEL(); # set this log level as default one

    if ( $verbosity == DEBUG_LOG_LEVEL() ) {
        return 'debug';
    }
    elsif ( $verbosity == INFO_LOG_LEVEL() ) {
        return 'info';
    }
    elsif ( $verbosity == NOTICE_LOG_LEVEL() ) {
        return 'notice';
    }
    else {
        return 'warning';
    }
}

1;

__END__

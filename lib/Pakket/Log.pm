package Pakket::Log;

# ABSTRACT: A logger for Pakket

use v5.22;
use strict;
use warnings;
use namespace::autoclean;

# core
use Carp;
use Sys::Syslog;
use Time::HiRes  qw(gettimeofday);
use experimental qw(declared_refs refaliasing signatures);

# non core
use IO::Interactive;
use JSON::MaybeXS qw(encode_json);
use Log::Dispatch::Screen::Gentoo;
use Log::Dispatch;
use Path::Tiny;
use Time::Format qw(time_format);
use Unicode::UTF8;

use constant {
    'DEBUG_LOG_LEVEL'  => 3,
    'INFO_LOG_LEVEL'   => 2,
    'NOTICE_LOG_LEVEL' => 1,

    'TERM_SIZE_MAX'     => 80,
    'TERM_EXTRA_SPACES' => (length (' * ') + length (' [ ok ]')),
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

sub send_data ($data, $started, $finished) {
    $data && $data->{'severity'}
        or return;

    $started && $finished
        and $data->{'took'} = $finished - $started;

    openlog('pakket', 'ndelay,pid');
    syslog($data->{'severity'}, encode_json($data));
    closelog();
    return;
}

sub build_logger ($class, $verbosity, $path = undef, $force_raw = 0) {
    my @outputs = ($class->_cli_logger($verbosity, $force_raw), $class->_syslog_logger());

    if ($path) {
        my $file = path($path);
        my $dir  = $file->parent();
        if (($file->exists && -w $file) || ($dir->exists && -w $dir)) {
            push (@outputs, $class->_file_logger($file->stringify));
        }
    }

    return Log::Dispatch->new(
        'outputs' => \@outputs,
    );
}

sub _cli_logger ($class, $verbosity, $force_raw = 0) {
    return [
        IO::Interactive::is_interactive() && !$force_raw ? 'Screen::Gentoo' : ('Screen', 'stderr' => 1),
        'min_level' => $class->_verbosity_to_loglevel($verbosity),
        'newline'   => 1,
        'utf8'      => 0,
        'callbacks' => [
            sub (%data) {
                return Unicode::UTF8::decode_utf8($data{'message'});
            },
        ],
    ];
}

sub _syslog_logger {
    return [
        'Syslog',
        'min_level' => 'warning',
        'ident'     => 'pakket',
        'callbacks' => [
            sub (%data) {
                return encode_json(\%data);
            },
        ],
    ];
}

sub _file_logger ($class, $file) {
    if (!$file) {
        my $dir = path('~/.pakket');
        eval {
            $dir->mkpath;
            1;
        } or do {
            croak "Can't create directory $dir : " . $!;
        };

        $file = $dir->child('pakket.log')->stringify;
    }

    return [
        'File',
        'min_level' => 'debug',
        'filename'  => $file,
        'newline'   => 1,
        'mode'      => '>>',
        'callbacks' => [
            sub (%data) {
                my $localtime = gettimeofday;
                my $timestr;

                eval {
                    $timestr = time_format('yyyy-mm-dd hh:mm:ss.mmm', $localtime);
                    1;
                } or do {
                    $timestr = time_format('yyyy-mm-dd hh:mm:ss.mmm', int ($localtime));
                };

                return sprintf '[%s] %.3s: %s', $timestr, $data{'level'}, $data{'message'};
            },
        ],
    ];
}

sub _verbosity_to_loglevel ($class, $verbosity = 0) {
    $verbosity ||= 0;
    $verbosity += NOTICE_LOG_LEVEL();                                          # set this log level as default one

    if ($verbosity >= DEBUG_LOG_LEVEL()) {
        return 'debug';
    } elsif ($verbosity == INFO_LOG_LEVEL()) {
        return 'info';
    } elsif ($verbosity == NOTICE_LOG_LEVEL()) {
        return 'notice';
    }

    return 'warning';
}

1;

__END__

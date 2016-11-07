package Pakket::Log;
# ABSTRACT: A logger for Pakket

use strict;
use warnings;
use Log::Dispatch;
use Path::Tiny qw< path >;

use constant {
    'DEBUG_LOG_LEVEL'    => 3,
    'DEBUG_INFO_LEVEL'   => 2,
    'DEBUG_NOTICE_LEVEL' => 1,
};

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
    my ( $class, $verbose ) = @_;
    my $logger = Log::Dispatch->new(
        'outputs' => [
            $class->_build_logger(),
            $class->_cli_logger( $verbose // 1 ),
        ],
    );

    return $logger;
}

sub _build_logger {
    return [
        'File',
        'min_level' => 'debug',
        'filename'  => path( Path::Tiny->cwd, 'build.log' )->stringify,
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
    # The default color map for Log::Dispatch::Screen::Color
    # is (to my eyes) really hard to read, let's make it saner.
    my $colors = {
        debug   => {
            text        => 'green',
        },
        info    => {
            text        => 'yellow',
        },
        error   => {
            background  => 'red',
        },
        alert   => {
            text        => 'red',
            background  => 'white',
        },
        warning => {
            text        => 'red',
            background  => 'white',
            bold        => 1,
        },
    };
    return [
        'Screen::Color',
        'min_level' => $screen_level,
        'newline'   => 1,
        'color'     => $colors,
    ];
}

1;

__END__

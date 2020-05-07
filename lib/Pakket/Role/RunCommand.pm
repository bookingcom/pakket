package Pakket::Role::RunCommand;

# ABSTRACT: Role for running commands

use v5.22;
use Moose::Role;
use namespace::autoclean;

# core
use Carp;
use English qw(-no_match_vars);
use File::chdir;
use System::Command;
use experimental qw(declared_refs refaliasing signatures);

# local
use Path::Tiny;

# does more or less the same as `command1 && command2 ... && commandN`
sub run_command_sequence ($self, $cwd, $common_opts, @commands) {
    @commands
        or return 1;

    $self->log->debugf('starting a sequence of %d commands', scalar @commands);
    for my $idx (0 .. $#commands) {
        my $success = $self->run_command($cwd, $common_opts, $commands[$idx]);
        if (!$success) {
            $self->log->notice('Sequence terminated on item:', $idx);
            return;
        }
    }
    $self->log->debug('sequence finished');
    return 1;
}

## no critic [Bangs::ProhibitBitwiseOperators]
sub run_command ($self, $cwd, $opts, $command) {
    my %opt = (
        'cwd' => path($cwd)->stringify,
        $opts->%*,

        # 'trace' => $ENV{SYSTEM_COMMAND_TRACE},
    );

    my $success;
    if (ref $command eq 'ARRAY') {
        my $cmd = System::Command->new($command->@*, \%opt);
        $self->log->notice('Command:', $cmd->cmdline);
        $success = $self->_do_run_command($cmd);
        if ($cmd->exit) {
            $self->log->error('Command:', join (' ', $cmd->cmdline), 'exited with', $cmd->exit);
        } else {
            $self->log->info('Command:', join (' ', $cmd->cmdline), 'exited with', $cmd->exit);
        }
    } else {
        $self->log->notice('Command:', $command);
        local $CWD = $cwd; ## no critic [Variables::ProhibitLocalVars]
        local %ENV = $opts->{'env'}->%*;
        my $errorcode = system ($command);
        $success = $errorcode == 0;
        if ($success) {
            $self->log->info('Command: ', $command, 'exited with', $errorcode);
        } else {
            if ($CHILD_ERROR == -1) {
                $self->log->errorf("Command: %s failed to execute: $!", $command);
            } elsif ($CHILD_ERROR & 127) {
                $self->log->errorf(
                    "Command '%s' died with signal %d, %s coredump",
                    $command,
                    ($CHILD_ERROR & 127),
                    ($CHILD_ERROR & 128) ? 'with' : 'without',
                );
            } else {
                local $EXTENDED_OS_ERROR = $CHILD_ERROR >> 8;                  # use $! to convert errorcode to errormessage
                $self->log->error('Command:', $command, 'exited with [', $EXTENDED_OS_ERROR, ']:',
                    "$EXTENDED_OS_ERROR");
            }
        }
    }

    return $success;
}

sub _do_run_command ($self, $cmd) {
    return $cmd->loop_on(
        'stdout' => sub ($msg) {
            chomp $msg;
            $self->log->debug($msg);
            1;
        },

        'stderr' => sub ($msg) {
            chomp $msg;
            $self->log->warn($msg);
            1;
        },
    );
}

before [qw(_do_run_command)] => sub ($self, @) {
    return $self->log_depth_change(+1);
};

after [qw(_do_run_command)] => sub ($self, @) {
    return $self->log_depth_change(-1);
};

1;

__END__

=pod

=head1 DESCRIPTION

Methods that help run commands in a standardized way.

=head1 METHODS

=head2 run_command

Run a command picking the directory it will run from and additional
options (such as environment or debugging). This uses
L<System::Command>.

    $self->run_command( $dir, $commands, $extra_opts );

    $self->run_command(
        '/tmp/mydir',
        [ 'echo', 'hello', 'world' ],

        # System::Command options
        { 'env' => { 'SHELL' => '/bin/bash' } },
    );

=head2 run_command_sequence

This method is useful when you want to run a sequence of commands in
which each commands depends on the previous one succeeding.

    $self->run_command_sequence(
        [ $dir, $commands, $extra_opts ],
        [ $dir, $commands, $extra_opts ],
    );

=head1 SEE ALSO

=over 4

=item * L<System::Command>

=back

=cut

package Pakket::Role::RunCommand;

# ABSTRACT: Role for running commands

use v5.22;
use Moose::Role;
use System::Command;
use Path::Tiny qw< path >;
use Log::Any qw< $log >;

sub run_command {
    my ($self, $dir, $sys_cmds, $extra_opts) = @_;
    $log->debug(join ' ', @{$sys_cmds});

    my %opt = (
        'cwd' => path($dir)->stringify,

        %{$extra_opts || {}},

        # 'trace' => $ENV{SYSTEM_COMMAND_TRACE},
    );

    my $cmd = System::Command->new(@{$sys_cmds}, \%opt);

    my $success = $cmd->loop_on(
        'stdout' => sub {
            my $msg = shift;
            chomp $msg;
            $log->debug($msg);
            1;
        },

        'stderr' => sub {
            my $msg = shift;
            chomp $msg;
            $log->notice($msg);
            1;
        },
    );

    $log->debugf("Command '%s' exited with '%d'", join (' ', $cmd->cmdline), $cmd->exit);

    return $success;
}

# does more or less the same as `command1 && command2 ... && commandN`
sub run_command_sequence {
    my ($self, @commands) = @_;

    $log->debugf('Starting a sequence of %d commands', 0 + @commands);

    for my $idx (0 .. $#commands) {
        my $success = $self->run_command(@{$commands[$idx]});
        unless ($success) {
            $log->debug("Sequence terminated on item $idx");
            return;
        }
    }

    $log->debug('Sequence finished');

    return 1;
}

no Moose::Role;

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

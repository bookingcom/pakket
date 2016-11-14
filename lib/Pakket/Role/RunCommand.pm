package Pakket::Role::RunCommand;
# ABSTRACT: Role for running commands

use Moose::Role;
use System::Command;
use Path::Tiny qw< path >;
use Log::Any   qw< $log >;

sub run_command {
    my ( $self, $dir, $sys_cmds, $extra_opts ) = @_;
    $log->info( join ' ', @{$sys_cmds} );
    foreach my $opt ( sort keys %{ $extra_opts->{'env'} || {} } ) {
        $log->trace( 'export ' . join '=', $opt, $extra_opts->{'env'}{$opt} );
    }

    my %opt = (
        'cwd' => path($dir)->stringify,

        %{ $extra_opts || {} },

        # 'trace' => $ENV{SYSTEM_COMMAND_TRACE},
    );

    my $cmd = System::Command->new( @{$sys_cmds}, \%opt );

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

    $log->debugf(
        "Command '%s' exited with '%d'",
        join( ' ', $cmd->cmdline ),
        $cmd->exit,
    );

    return $success;
}

# does more or less the same as `command1 && command2 ... && commandN`
sub run_command_sequence {
    my ( $self, @commands ) = @_;

    $log->debugf( 'Starting a sequence of %d commands', 0+@commands );

    for my $idx ( 0 .. $#commands ) {
        my $success = $self->run_command( @{ $commands[$idx] } );
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

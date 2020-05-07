package Pakket::Role::ParallelInstaller;

# ABSTRACT: Enables parallel installation

use v5.22;
use Moose::Role;
use namespace::autoclean;

# core
use Carp;
use List::Util qw(any min);
use POSIX qw(:sys_wait_h);
use Time::HiRes qw(time usleep);
use experimental qw(declared_refs refaliasing signatures);

# non core
use Data::Consumer::Dir;

use constant {
    'MAX_SUBPROCESSES'        => 3,
    'PACKAGES_PER_SUBPROCESS' => 100,
    'SLEEP_TIME_USEC'         => 100_000,
    'NEXT_FORK_WAIT_SEC'      => 1,
    'TIME_SHIFT'              => 10_000,
};

has 'jobs' => (
    'is'      => 'ro',
    'isa'     => 'Int',
    'default' => 1,
);

has 'is_child' => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'default' => 0,
);

has 'data_consumer_dir' => (
    'is'      => 'ro',
    'lazy'    => 1,
    'default' => sub($self) {
        my $dc_dir = $self->work_dir->child('.install_queue');
        $self->log->trace('creating data_consumer_dir:', $dc_dir);
        $dc_dir->child('unprocessed')->mkpath;
        $dc_dir->child('to_install')->mkpath;
        return $dc_dir;
    },
);

has 'data_consumer' => (
    'is'      => 'ro',
    'lazy'    => 1,
    'default' => sub($self) {
        return Data::Consumer::Dir->new(
            'root'       => $self->data_consumer_dir,
            'create'     => 1,
            'open_mode'  => '+<',
            'max_failed' => $self->continue ? 0 : 5,
        );
    },
);

has '_children' => (
    'is'      => 'ro',
    'isa'     => 'ArrayRef',
    'default' => sub {[]},
);

has '_to_process' => (
    'is'      => 'ro',
    'isa'     => 'Int',
    'default' => 0,
);

has '_data_consumer_queue' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'default' => sub {+{}},
);

sub BUILD ($self, @) {
    if ($self->jobs < 1 || $self->jobs > MAX_SUBPROCESSES() + 1) {
        croak($self->log->criticalf('Incorrect jobs value: %s (must be 1 .. 4)', $self->jobs));
    }
}

sub spawn_workers($self) {
    my $subprocs = $self->_subproc_count;
    $subprocs and $self->log->notice('Spawning additional processes', $subprocs);
    for (1 .. $subprocs) {
        my $child = fork;
        if (not defined $child) {
            croak("Fork failed: $!");
        } elsif ($child) {
            push @{$self->{'_children'}}, $child;
            sleep (NEXT_FORK_WAIT_SEC());
        } else {
            $self->{'is_child'} = 1;
            return;
        }
    }

    return;
}

sub wait_workers($self) {
    $self->is_child
        and exit 0;

    my @children = $self->_children->@*;
    while (@children) {
        @children = grep {0 == waitpid ($_, WNOHANG)} @children;
        usleep(SLEEP_TIME_USEC());
    }

    return;
}

sub is_parallel($self) {
    my $j = $self->jobs;

    return defined $j && $j > 1;
}

sub push_to_data_consumer ($self, $pkg, $opts = {}) {
    my $pkg_esc  = _escape_filename($pkg);
    my $filename = sprintf ('%014d-%s', time * TIME_SHIFT(), $pkg_esc);

    my \%queue = $self->_data_consumer_queue;
    $queue{$pkg}
        and $self->log->debug('package is already in the queue:', $pkg)
        and return;

    $queue{$pkg}++;                                                            # mark this package as processing
    my $dir  = $self->data_consumer_dir;
    my @dirs = grep -d, map {$dir->child($_)} qw(unprocessed working failed processed);

    grep -e, map {$_->children(qr/\d{14}-\Q$pkg_esc\E$/ms)} @dirs
        and $self->log->trace('package is already in the consuming dirs:', $pkg)
        and return;

    my $as_prereq = int (!!$opts->{'as_prereq'});

    $self->log->debug('package is added to the queue:', $pkg);
    $dir->child('unprocessed' => $filename)->spew($as_prereq . $pkg);
    $self->{'_to_process'}++;

    return;
}

sub _subproc_count ($self) {
    return min(MAX_SUBPROCESSES(), $self->jobs - 1, abs int ($self->_to_process / PACKAGES_PER_SUBPROCESS()));
}

sub _escape_filename($file) {
    return $file =~ s{[^[:alnum:].]+}{-}grxms;
}

1;

__END__

package Pakket::Role::ParallelInstaller;
# ABSTRACT: Enables parallel installation

use v5.22;
use Moose::Role;

use Carp        qw < croak >;
use Data::Consumer::Dir;
use List::Util  qw< any min >;
use Log::Any    qw< $log >;
use POSIX       ':sys_wait_h';
use Time::HiRes qw< time usleep >;

use constant {
    'MAX_SUBPROCESSES'        => 3,
    'PACKAGES_PER_SUBPROCESS' => 100,
    'SLEEP_TIME_USEC'         => 100_000,
    'NEXT_FORK_WAIT_SEC'      => 1,
    'TIME_SHIFT'              => 10_000,
};

has 'jobs' => (
    'is'        => 'ro',
    'isa'       => 'Maybe[Int]',
);

has 'is_child' => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'default' => sub {0},
);

has '_children' => (
    'is'      => 'ro',
    'isa'     => 'ArrayRef',
    'default' => sub {[]},
);

has '_to_process' => (
    'is'      => 'ro',
    'isa'     => 'Int',
    'default' => sub {0},
);

has 'data_consumer_dir' => (
    'is'      => 'ro',
    'lazy'    => 1,
    'default' => sub {
        my ($self) = @_;
        my $dc_dir = $self->work_dir->child('.install_queue');
        $dc_dir->child('unprocessed')->mkpath;
        $dc_dir->child('to_install')->mkpath;
        return $dc_dir;
    },
);

has 'data_consumer' => (
    'is'      => 'ro',
    'lazy'    => 1,
    'default' => sub {
        my ($self) = @_;

        return Data::Consumer::Dir->new(
            'root'       => $self->data_consumer_dir,
            'create'     => 1,
            'open_mode'  => '+<',
            'max_failed' => $self->ignore_failures ? 0 : 5,
        );
    },
);

sub BUILD {
    my ($self) = @_;

    if (defined $self->jobs && ($self->jobs < 1 || $self->jobs > MAX_SUBPROCESSES() + 1)) {
        croak($log->criticalf('Incorrect jobs value: %s (must be 1 .. 4)', $self->jobs));
    }
}

sub spawn {
    my ($self) = @_;

    my $subprocs = $self->_subproc_count;
    $subprocs and $log->infof('Spawning %s additional processes', $subprocs);
    for ( 1 .. $subprocs ) {
        my $child = fork;
        if ( not defined $child ) {
            croak "Fork failed: $!";
        }
        elsif ($child) {
            push @{ $self->{'_children'} }, $child;
            sleep(NEXT_FORK_WAIT_SEC());
        }
        else {
            $self->{'is_child'} = 1;
            return;
        }
    }

    return;
}

sub wait_all_children {
    my ($self) = @_;

    $self->is_child and exit(0);

    my @children = @{ $self->_children };
    while (@children) {
        @children = grep { 0 == waitpid( $_, WNOHANG ) } @children;
        usleep(SLEEP_TIME_USEC());
    }

    return;
}

sub is_parallel {
    my ($self) = @_;

    my $j = $self->jobs;

    return defined $j && $j > 1;
}

sub push_to_data_consumer {
    my ( $self, $pkg, $opts ) = @_;

    my $pkg_esc  = _escape_filename($pkg);
    my $filename = sprintf( '%014d-%s', time * TIME_SHIFT(), $pkg_esc );
    my $dir      = $self->data_consumer_dir;

    # if it's already in the queue, return
    my @dirs = grep -d, map { $dir->child($_) } qw(unprocessed working failed processed);
    return if grep -e, map { $_->children(qr/\d{14}-\Q$pkg_esc\E$/ms) } @dirs; ## no critic (Perl::Critic::Policy::BuiltinFunctions::ProhibitBooleanGrep)

    my $as_prereq = int !!$opts->{'as_prereq'};

    $dir->child( 'unprocessed' => $filename )->spew( $as_prereq . $pkg );
    $self->{'_to_process'}++;

    return;
}

sub _subproc_count {
    my ($self) = @_;

    return min(MAX_SUBPROCESSES(), $self->jobs - 1, abs int($self->_to_process / PACKAGES_PER_SUBPROCESS()));
}

sub _escape_filename {
    my ($file) = @_;

    return $file =~ s/[^a-zA-Z0-9\.]+/-/grsm;
}

no Moose::Role;

1;

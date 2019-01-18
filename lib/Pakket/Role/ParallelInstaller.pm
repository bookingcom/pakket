package Pakket::Role::ParallelInstaller;
# ABSTRACT: Enables parallel installation

use Moose::Role;
use Data::Consumer::Dir;
use POSIX ":sys_wait_h";
use Time::HiRes qw< time usleep >;

has 'jobs' => (
    'is'        => 'ro',
    'isa'       => 'Maybe[Int]',
);

has _children => (
    is => 'ro',
    lazy => 1,
    default => sub {
        my $self = shift;
        my $child;
        my @children;
        my $procs = $self->jobs - 1; # parent is already created

        do {
            $child = fork;
            if ( !defined $child ) {
                die "Fork failed: $!";
            } elsif ($child) {
                push @children, $child;
            }
        } while $child and --$procs > 0;

        # child process has no children
        if (!$child) {
            return [];
        }

        # parent has children
        return \@children;
    }
);

has data_consumer_dir => (
    is => 'ro',
    lazy => 1,
    default => sub {
        my $self = shift;
        my $dir = $self->work_dir;
        my $dc_dir = $dir->child('.install_queue');
        $dc_dir->child('unprocessed')->mkpath;
        $dc_dir->child('to_install')->mkpath;
        return $dc_dir;
    }
);

has data_consumer => (
    is => 'ro',
    lazy => 1,
    default => sub {
        my $self = shift;

        return Data::Consumer::Dir->new(
            root       => $self->data_consumer_dir,
            create     => 1,
            open_mode  => '+<',
            max_failed => int !$self->ignore_failures,
        );
    },
);

sub spawn {
    my ($self) = @_;
    $self->_children;
    return;
}

sub is_parent {
    my ($self) = @_;
    return @{ $self->_children } > 0;
}

sub wait_all_children {
    my ($self) = @_;

    exit(0) if !$self->is_parent;
    my @child = @{ $self->_children };

    while (@child) {
        @child = grep { waitpid( $_, WNOHANG ) == 0 } @child;
        usleep 100;
    }

    return;
}

sub is_parallel {
    my ($self) = @_;
    my $j = $self->jobs;
    defined $j && $j > 1;
}

sub _escape_filename {
    my $file = shift;
    return $file =~ s/[^a-zA-Z0-9\.]+/-/gr;
}

sub _push_to_data_consumer {
    my ( $self, $pkg, $opts ) = @_;
    my $pkg_esc = _escape_filename($pkg);
    my $filename = sprintf( "%014d-%s", time * 10000, $pkg_esc );
    my $dir = $self->data_consumer_dir;

    # if it's already in the queue, return
    return
        if grep -e, map $_->children(qr/\d{14}-\Q$pkg_esc\E$/), grep -d,
        map $dir->child($_), qw(unprocessed working failed processed);

    my $as_prereq = int !! $opts->{as_prereq};

    $dir->child( unprocessed => $filename )->append($as_prereq . $pkg);
}


no Moose::Role;
1;

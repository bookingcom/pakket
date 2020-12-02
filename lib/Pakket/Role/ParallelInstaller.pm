package Pakket::Role::ParallelInstaller;

# ABSTRACT: Enables parallel installation

use v5.22;
use autodie;
use Moose::Role;
use namespace::autoclean;

# core
use Carp;
use Fcntl qw(:flock);
use English qw(-no_match_vars);
use List::Util qw(any min);
use POSIX qw(:sys_wait_h);
use Time::HiRes qw(time usleep);
use experimental qw(declared_refs refaliasing signatures);

# non core
use Data::Consumer::Dir;
use JSON::MaybeXS;
use Path::Tiny;

use constant {
    'MAX_SUBPROCESSES'        => 7,
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
        my $dc_dir = Path::Tiny->tempdir('.install-queue-XXXXXXXXXX', DIR => $self->work_dir->absolute->stringify);
        $self->log->trace('creating data_consumer_dir:', $dc_dir);
        $dc_dir->child('unprocessed')->mkpath;
        $dc_dir->child('to_install')->mkpath;
        $dc_dir->child('all')->mkpath;
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

around push_to_data_consumer => sub ($what, $self, $requirements, %options) {
    state $cache_dir = $self->data_consumer_dir->child('all');
    open (my $cachedir_fh, '<', $cache_dir->stringify);
    flock ($cachedir_fh, LOCK_EX);
    eval {
        $self->$what($requirements, %options);
        1;
    } or do {
        my $error = $@ || 'zombie error';
        flock ($cachedir_fh, LOCK_UN);
        close ($cachedir_fh);
        die $error; ## no critic [ErrorHandling::RequireCarping]
    };
    flock ($cachedir_fh, LOCK_UN);
    close ($cachedir_fh);

    return;
};

sub push_to_data_consumer ($self, $requirements, %options) {
    $requirements->%*
        or return;

    my \%queue = $self->_update_cache;

    my (\@found, \@not_found) = $self->filter_packages_in_cache($requirements, $self->_data_consumer_queue->{'index'});
    @not_found
        or return;

    my \@packages = $self->parcel_repo->select_available_packages($requirements, 'continue' => $self->continue);

    my $dir = $self->data_consumer_dir;
    $self->{'_to_process'} += scalar @packages;
    foreach my $package (@packages) {
        if (exists $queue{'index'}{$package->short_name}) {
            $self->log->warnf(
                'Dependency conflict detected. Package %s has version incompatible with version pinned in the request. Skipping',
                $package->id,
            );
            next;                                                              # temporary solution. later warn should be changed to die
        }
        $self->log->debug('adding package to the queue:', $package->id);
        my $data = {
            'short_name' => $package->short_name,
            'version'    => $package->version,
            'release'    => $package->release,
            'as_prereq'  => $package->as_prereq // $options{'as_prereq'} // 0,
        };
        my $encoded_data = encode_json($data);

        my $filename = sprintf ('%014d%06d-%s.json', time * TIME_SHIFT(), $PID, _escape_filename($package->name));
        $queue{'index'}{$package->short_name}{$package->version}{$package->release}++;
        $queue{$filename} = $data;
        $dir->child('all'         => $filename)->spew($encoded_data);          # put file into quieue cache
        $dir->child('unprocessed' => $filename)->spew($encoded_data);          # put file into consumer queue
    }

    return;
}

sub _update_cache ($self) {
    state \%queue = $self->_data_consumer_queue;
    state $cache_dir = $self->data_consumer_dir->child('all');

    my %files = map {+($_->basename => $_)} $cache_dir->children(qr/json\z$/);
    delete @files{keys %queue};

    foreach my $file (keys %files) {
        my $data = decode_json($files{$file}->slurp);
        $queue{$file} = $data;
        $queue{'index'}{$data->{'short_name'}}{$data->{'version'}}{$data->{'release'}}++;
    }

    return \%queue;
}

sub _subproc_count ($self) {
    return min(MAX_SUBPROCESSES(), $self->jobs - 1, abs int ($self->_to_process / PACKAGES_PER_SUBPROCESS()));
}

sub _escape_filename($file) {
    return $file =~ s{[^[:alnum:].]+}{-}grxms;
}

1;

__END__

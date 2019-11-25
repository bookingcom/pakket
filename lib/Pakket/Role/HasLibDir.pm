package Pakket::Role::HasLibDir;

# ABSTRACT: a Role to add lib directory functionality

use v5.22;
use Moose::Role;

use Carp qw< croak >;
use Path::Tiny qw< path  >;
use Types::Path::Tiny qw< Path  >;
use File::Copy::Recursive qw< dircopy >;
use File::Lockfile;
use Time::HiRes qw< time >;
use Log::Any qw< $log >;
use English qw< -no_match_vars >;
use Errno qw< :POSIX >;

has 'pakket_dir' => (
    'is'       => 'ro',
    'isa'      => Path,
    'coerce'   => 1,
    'required' => 1,
);

has 'libraries_dir' => (
    'is'      => 'ro',
    'isa'     => Path,
    'coerce'  => 1,
    'lazy'    => 1,
    'builder' => '_build_libraries_dir',
);

has 'active_dir' => (
    'is'      => 'ro',
    'isa'     => Path,
    'coerce'  => 1,
    'lazy'    => 1,
    'builder' => '_build_active_dir',
);

has 'work_dir' => (
    'is'      => 'ro',
    'isa'     => Path,
    'coerce'  => 1,
    'lazy'    => 1,
    'builder' => '_build_work_dir',
);

has 'lock' => (
    'is' => 'rw',
);

has 'atomic' => (
    'is'      => 'ro',
    'default' => 1,
);

has [qw< use_hardlinks allow_rollback >] => (
    'is'      => 'ro',
    'default' => 0,
);

has 'rollback_tag' => (
    'is'      => 'ro',
    'isa'     => 'Str',
    'default' => '',
);

has 'keep_rollbacks' => (
    'is'      => 'ro',
    'default' => 1,
);

sub _build_libraries_dir {
    my $self = shift;

    my $libraries_dir = $self->pakket_dir->child('libraries');

    $libraries_dir->is_dir
        or $libraries_dir->mkpath();

    return $libraries_dir;
}

sub _build_active_dir {
    my $self = shift;

    my $active_dir = $self->libraries_dir->child('active');

    if (!$self->atomic && !$active_dir->exists) {
        $active_dir->mkpath;
    }

    return $active_dir;
}

sub _build_work_dir {
    my $self = shift;

    $self->pakket_dir->is_dir
        or $self->pakket_dir->mkpath();

    $self->lock_lib_directory();

    if (!$self->atomic) {
        $log->debugf('Atomic mode disabled: using %s as working directory', $self->active_dir->stringify);
        return $self->active_dir;
    }

    my $work_dir;
    $work_dir = eval {$self->_create_and_fill_workdir($self->rollback_tag, 1)} if $self->use_hardlinks;
    $work_dir //= $self->_create_and_fill_workdir($self->rollback_tag);

    return $work_dir;
}

sub _create_and_fill_workdir {
    my ($self, $tag, $use_hardlinks) = @_;

    my $template = sprintf ("%s/work_%s_%s_XXXXX", $self->libraries_dir, $PID, time ());
    my $work_dir = Path::Tiny->tempdir(
        $template,
        TMPDIR  => 0,
        CLEANUP => 1
    );

    $work_dir->exists
        or croak($log->critical("Could not create installation directory ($work_dir), exiting"));

    # we copy any previous installation
    if ($self->active_dir->exists) {
        my $orig_work_dir = eval {my $link = readlink $self->active_dir} or do {
            croak($log->critical("$self->active_dir is not a symlink"));
        };

        my $source = $self->libraries_dir->child($orig_work_dir);
        my $dest   = $work_dir;
        if ($use_hardlinks) {
            my $cmd   = "cp -al '$source'/* '$dest' && rm -f '$dest'/info.json && cp -af '$source'/info.json '$dest'";
            my $ecode = system ($cmd);

            if ($ecode) {
                $log->warn("error: $ecode. Unable to prepare workdir with hardlinks $dest");
                die;
            }
            1;
        } else {
            dircopy($source, $dest);
        }
    }
    $log->debugf('Created new working directory %s', "$work_dir");

    return $work_dir;
}

sub activate_dir {
    my ($self, $dir) = @_;

    if (!$self->atomic) {
        $log->debug("Atomic mode disabled: skipping activation of dir");
        return;
    }

    if ($self->active_dir->exists && -l $self->active_dir) {
        my $link = readlink $self->active_dir;

        if ($self->libraries_dir->child($link) eq $dir) {
            $log->debugf('Directory %s is already active', $dir);
            return EEXIST;
        }
    }

    # The only way to make a symlink point somewhere else in an atomic way is
    # to create a new symlink pointing to the target, and then rename it to the
    # existing symlink (that is, overwriting it).
    #
    # This actually works, but there is a caveat: how to generate a name for
    # the new symlink? File::Temp will both create a new file name and open it,
    # returning a handle; not what we need.
    #
    # So, we just create a file name that looks like 'active_P_T.tmp', where P
    # is the pid and T is the current time.
    my $active_temp = $self->libraries_dir->child(sprintf ('active_%s_%s.tmp', $PID, time ()));

    if ($active_temp->exists) {

        # Huh? why does this temporary pathname exist? Try to delete it...
        $log->debug('Deleting existing temporary active object');
        $active_temp->remove
            or croak($log->error('Could not activate new installation (temporary symlink remove failed)'));
    }

    # Need to set proper permissions before we move the work directory
    $dir->chmod('0755');

    my $work_final = $self->libraries_dir->child(time ());
    $log->debugf('Moving work directory %s to its final place %s', "$dir", "$work_final");
    $dir->move($work_final)
        or croak($log->error('Could not move work_dir to its final place'));

    $log->debugf('Setting temporary active symlink to new work directory %s', "$work_final");
    symlink ($work_final->basename, $active_temp)
        or croak($log->error('Could not activate new installation (temporary symlink create failed)'));

    $log->debugf('Moving symlink %s to its final place %s', "$active_temp", $self->active_dir->stringify);
    $active_temp->move($self->active_dir)
        or croak($log->error('Could not atomically activate new installation (symlink rename failed)'));

    $self->remove_old_libraries($work_final);
    return 0;
}

sub activate_work_dir {
    my $self = shift;

    if (!$self->atomic) {
        $log->debug("Atomic mode disabled: skipping activation of work dir");
        return;
    }

    my $work_dir = $self->work_dir;

    $self->activate_dir($work_dir);
}

sub remove_old_libraries {
    my ($self, $work_dir) = @_;

    if (!$self->atomic) {
        $log->debug("Atomic mode disabled: skipping removal of old libraries");
        return;
    }

    my @dirs = grep {$_->basename ne 'active' && $_ ne $work_dir && $_->is_dir} $self->libraries_dir->children;

    my $num_dirs = @dirs;
    foreach my $dir (@dirs) {
        $num_dirs-- < $self->keep_rollbacks and last;
        $log->debug("Removing old directory: $dir");
        path($dir)->remove_tree({'safe' => 0});
    }
}

sub lock_lib_directory {
    my $self = shift;

    my $lock = File::Lockfile->new('lock.pid', $self->pakket_dir);
    if (my $pid = $lock->check) {
        croak($log->critical("Seems that pakket for is already running with PID: $pid"));
    }
    $lock->write;
    $self->lock($lock);
}

sub DEMOLISH {
    my $self = shift;
    if ($self->lock) {
        $self->lock->remove;
    }
}

no Moose::Role;
1;
__END__

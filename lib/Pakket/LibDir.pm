package Pakket::LibDir;

# ABSTRACT: Function to work with lib directory

use Path::Tiny qw< path  >;
use File::Copy::Recursive qw< dircopy >;
use Time::HiRes qw< time >;
use Log::Any qw< $log >;
use English qw< -no_match_vars >;

sub get_libraries_dir {
    my $lib_dir = shift;

    my $libraries_dir = $lib_dir->child('libraries');

    $libraries_dir->is_dir
        or $libraries_dir->mkpath();

    return $libraries_dir;
}

sub get_active_dir {
    my $lib_dir = shift;

    my $active_dir = get_libraries_dir($lib_dir)->child('active');

    return $active_dir;
}

sub create_new_work_dir {
    my $pakket_dir = shift;

    my $pakket_libraries_dir = get_libraries_dir($pakket_dir);

    my $work_dir = $pakket_libraries_dir->child( time() );

    if ( $work_dir->exists ) {
        die $log->critical(
            "Internal installation directory exists ($work_dir), exiting",
        );
    }

    $work_dir->mkpath();

    my $active_link = get_active_dir($pakket_dir);

    # we copy any previous installation
    if ( $active_link->exists ) {
        my $orig_work_dir = eval { my $link = readlink $active_link } or do {
            die $log->critical("$active_link is not a symlink");
        };

        dircopy( $pakket_libraries_dir->child($orig_work_dir), $work_dir );
    }
    $log->debugf( 'Created new working directory %s', $work_dir );
    return $work_dir;
}

sub activate_work_dir {
    my $work_dir = shift;

    unless ( $work_dir->exists ) {
        die $log->critical("Directory $work_dir doesn't exist");
    }

    my $pakket_libraries_dir = $work_dir->parent;

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
    my $active_link = $pakket_libraries_dir->child('active');
    my $active_temp
        = $pakket_libraries_dir->child(
        sprintf( 'active_%s_%s.tmp', $PID, time() ),
        );

    if ( $active_temp->exists ) {

        # Huh? why does this temporary pathname exist? Try to delete it...
        $log->debug('Deleting existing temporary active object');
        if ( !$active_temp->remove ) {
            die $log->error(
                'Could not activate new installation (temporary symlink remove failed)'
            );
        }
    }

    $log->debugf( 'Setting temporary active symlink to new work directory %s',
        $work_dir );
    if ( !symlink $work_dir->basename, $active_temp ) {
        die $log->error(
            'Could not activate new installation (temporary symlink create failed)'
        );
    }
    if ( !$active_temp->move($active_link) ) {
        die $log->error(
            'Could not atomically activate new installation (symlink rename failed)'
        );
    }
}

sub remove_old_libraries {
    my $lib_dir              = shift;
    my $pakket_libraries_dir = get_libraries_dir($lib_dir);

    my $keep = 1;

    my @dirs = sort { $a->stat->mtime <=> $b->stat->mtime }
        grep +( $_->basename ne 'active' && $_->is_dir ),
        $pakket_libraries_dir->children;

    my $num_dirs = @dirs;
    foreach my $dir (@dirs) {
        $num_dirs-- <= $keep and last;
        $log->debug("Removing old directory: $dir");
        path($dir)->remove_tree( { 'safe' => 0 } );
    }
}

1;

__END__

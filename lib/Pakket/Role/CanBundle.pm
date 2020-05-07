package Pakket::Role::CanBundle;

# ABSTRACT: Role to bundle pakket packages into a parcel file

use v5.22;
use Moose::Role;
use namespace::autoclean;

# core
use Carp;
use File::chdir;
use File::Spec;
use experimental qw(declared_refs refaliasing signatures);

# non core
use Algorithm::Diff::Callback qw(diff_hashes);
use JSON::MaybeXS;
use Path::Tiny;
use Types::Path::Tiny qw(AbsPath);

# local
use Pakket::Constants qw(
    PARCEL_FILES_DIR
    PARCEL_METADATA_FILE
);
use Pakket::Repository::Parcel;
use Pakket::Type::Package;
use Pakket::Utils qw(encode_json_pretty);

has [qw(dry_run)] => (
    'is'  => 'ro',
    'isa' => 'Int',
);

has [qw(build_files_manifest)] => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'default' => sub {+{}},
);

has '_files_to_skip' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'traits'  => ['Hash'],
    'handles' => {'should_skip_file' => 'exists'},
    'default' => sub {
        +{
            'perllocal.pod' => undef,
        };
    },
);

sub bundle ($self, $package, $build_dir, $files) {
    my $parcel_dir = Path::Tiny->tempdir(
        'TEMPLATE' => 'pakket-bundle-' . $package->name . '-XXXXXXXXXX',
        'CLEANUP'  => 1,
    );
    my $target = $parcel_dir->child(PARCEL_FILES_DIR());
    $target->mkpath;

    foreach my $file (keys $files->%*) {
        $self->log->debug('bundling file:', $file);
        my $spath = path($file);
        my $tpath = $target->child($spath->relative($build_dir));

        $tpath->exists
            and $self->croak('File already seems to exist in packaging dir. Stopping');

        $tpath->parent->mkpath;                                                # create directories

        if ($files->{$file} eq '') {                                           # regular file
            $spath->copy($tpath);
            $tpath->chmod((stat ($file))[2] & oct ('07777')); ## no critic [Bangs::ProhibitBitwiseOperators]
        } else {                                                               # symlink
            symlink $files->{$file}, $tpath
                or $self->croak('Unable to symlink');
        }
    }

    if (!$self->dry_run) {
        $self->log->notice('Creating parcel file for:', $package->id);
        $target->child(PARCEL_METADATA_FILE())->spew_utf8(encode_json_pretty($package->spec));
        $self->parcel_repo->store_package($package, $parcel_dir);
    }

    return;
}

sub snapshot_build_dir ($self, $package, $build_dir, $silent = 1) {
    $build_dir
        or croak('bla');

    $self->log->debug('scanning directory:', $build_dir);

    my $package_files = $self->retrieve_new_files($build_dir);

    !$silent && !$package_files->%*
        and $self->croak('Build did not generate new files. Cannot package:', $package->id);

    $self->build_files_manifest->@{keys ($package_files->%*)} = values $package_files->%*;

    return $self->normalize_paths($package_files);
}

sub retrieve_new_files ($self, $build_dir) {
    my $nodes = $self->_scan_directory($build_dir);
    return $self->_diff_nodes_list($self->build_files_manifest, $nodes);
}

sub normalize_paths ($self, $package_files) {
    my $paths;
    for my $path_and_timestamp (keys $package_files->%*) {
        my ($path) = $path_and_timestamp =~ /^(.+)_\d+?$/;
        $paths->{$path} = $package_files->{$path_and_timestamp};
    }
    return $paths;
}

sub _scan_directory ($self, $dir) {
    my $visitor = sub ($node, $state) {
        $node->is_dir || $self->should_skip_file($node->basename)
            and return;

        my $path_and_timestamp = sprintf ('%s_%s', $node->absolute, $node->stat->ctime);

        # save the symlink path in order to symlink them
        if (-l $node) {
            path($state->{$path_and_timestamp} = readlink $node)->is_absolute
                and $self->croak("Error. Absolute path symlinks aren't supported.");
        } else {
            $state->{$path_and_timestamp} = '';
        }
    };

    return $dir->visit(
        $visitor,
        {
            'recurse'         => 1,
            'follow_symlinks' => 0,
        },
    );
}

sub _diff_nodes_list ($self, $old_nodes, $new_nodes) {
    my %nodes_diff;
    diff_hashes($old_nodes, $new_nodes, 'added' => sub ($key, $value) {$nodes_diff{$key} = $value});
    return \%nodes_diff;
}

sub fix_timestamps ($src_dir, $dst_dir) {
    $src_dir->visit(
        sub ($src, $) {
            my $dst = path($dst_dir, $src->relative($src_dir));
            $dst->touch($src->stat->mtime);
        },
        {'recurse' => 1},
    );
    return;
}

before [qw(bundle)] => sub ($self, @) {
    return $self->log_depth_change(+1);
};

after [qw(bundle)] => sub ($self, @) {
    return $self->log_depth_change(-1);
};

1;

__END__

=pod

=head1 SYNOPSIS

    use Pakket::Role::CanBundle;

=head1 DESCRIPTION

The Pakket::Role::CanBundle

=head1 ATTRIBUTES

=head2 build_files_manifest

After building, the list of built files are stored in this hashref.

=head1 METHODS

=head2 normalize_paths(\%package_files);

Given a set of paths and timestamps, returns a new hashref with
normalized paths.

=head2 retrieve_new_files($build_dir)

Once a build has finished, we attempt to install the directory to a
controlled environment. This method scans that directory to find any
new files generated. This is determined to get packaged in the parcel.

=head2 snapshot_build_dir( $package, $build_dir, $error_out )

This method generates the manifest list for the parcel from the scanned
files.

=cut

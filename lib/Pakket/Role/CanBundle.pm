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

has [qw(_files_manifests)] => (
    'is'      => 'ro',
    'isa'     => 'ArrayRef',
    'default' => sub {+[]},
);

has '_files_to_skip' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'traits'  => ['Hash'],
    'handles' => {'should_skip_file' => 'exists'},
    'default' => sub {
        +{
            '.packlist'     => undef,
            'perllocal.pod' => undef,
        };
    },
);

sub bundle ($self, $package, $build_dir) {
    $self->_files_manifests->@* >= 2
        or $self->croak('Bundle can be done only based on at least 2 snapshots created');

    my $parcel_dir = Path::Tiny->tempdir(
        'TEMPLATE' => 'pakket-bundle-' . $package->name . '-XXXXXXXXXX',
        'CLEANUP'  => 1,
    );
    my $target = $parcel_dir->child(PARCEL_FILES_DIR());
    $target->mkpath;

    my \%new_or_updated_files = $self->_diff_nodes_list($self->_files_manifests->@[0, -1]);

    foreach my $key (sort keys %new_or_updated_files) {
        my $abs_path = path($new_or_updated_files{$key});

        my $target_path = $target->child($abs_path->relative($build_dir));

        $target_path->exists
            and $self->croak('Stopping. File already seems to exist in packaging dir:', $target_path);

        $target_path->parent->mkpath;
        if (-l $abs_path) {
            $self->log->debugf('bundling file: %s -> %s', $abs_path, readlink ($abs_path));
            symlink (readlink ($abs_path), $target_path)
                or $self->croak('Unable to symlink:', $target_path);
        } else {
            $self->log->debug('bundling file:', $abs_path);
            $abs_path->copy($target_path);
            $target_path->chmod($abs_path->lstat->mode & oct ('07777')); ## no critic [Bangs::ProhibitBitwiseOperators]
        }
    }

    if (!$self->dry_run) {
        $self->log->notice('Creating parcel file for:', $package->id);
        $target->child(PARCEL_METADATA_FILE())->spew_utf8(encode_json_pretty($package->spec));
        $self->parcel_repo->store_package($package, $parcel_dir);
    }

    return;
}

sub snapshot_build_dir ($self, $package, $build_dir, $silent = 0) {
    $build_dir
        or croak('Build dir is not set');

    $self->log->debug('scanning directory:', $build_dir);

    my \%package_files = $self->_scan_directory($build_dir);

    $silent || %package_files
        or $self->croak('Build did not generate new files. Cannot package:', $package->id);

    $self->log->debug('files snapshotted:', scalar %package_files);
    push $self->_files_manifests->@*, \%package_files;

    return;
}

sub _scan_directory ($self, $dir) {
    $dir->mkpath;
    return $dir->realpath->visit(
        sub ($node, $state) {
            -l $node || ($node->is_file && !$self->should_skip_file($node->basename))
                or return;

            my $stat = $node->lstat;
            my $key  = sprintf ('%s-mtime(%s)', $node->absolute, $stat->mtime);
            $state->{$key} = $node->absolute;
        },
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

=head1 METHODS

=head2 snapshot_build_dir( $package, $build_dir, $error_out )

This method generates the manifest list for the parcel from the scanned
files.

=cut

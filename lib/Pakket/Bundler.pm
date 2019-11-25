package Pakket::Bundler;

# ABSTRACT: Bundle pakket packages into a parcel file

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use JSON::MaybeXS;
use File::chdir;
use File::Spec;
use Carp qw< croak >;
use Path::Tiny qw< path >;
use Types::Path::Tiny qw< AbsPath >;
use Log::Any qw< $log >;

use Pakket::Package;
use Pakket::Repository::Parcel;

use Pakket::Constants qw<
    PARCEL_FILES_DIR
    PARCEL_METADATA_FILE
>;

use Pakket::Utils qw< encode_json_pretty >;

use constant {
    'BUNDLE_DIR_TEMPLATE' => 'BUNDLE-XXXXXX',
};

with qw<
    Pakket::Role::HasConfig
    Pakket::Role::HasParcelRepo
>;

sub bundle {
    my ($self, $build_dir, $package, $files) = @_;

    my $original_dir    = Path::Tiny->cwd;
    my $parcel_dir_path = Path::Tiny->tempdir(
        'TEMPLATE' => BUNDLE_DIR_TEMPLATE(),
        'CLEANUP'  => 1,
    );

    $parcel_dir_path->child(PARCEL_FILES_DIR())->mkpath;

    chdir $parcel_dir_path->child(PARCEL_FILES_DIR())->stringify;

    foreach my $orig_file (keys %{$files}) {
        $log->debug("Bundling $orig_file");
        my $new_fullname = $self->_rebase_build_to_output_dir($build_dir, $orig_file);

        -e $new_fullname
            and croak('Odd. File already seems to exist in packaging dir. ' . "Stopping.\n");

        # create directories
        $new_fullname->parent->mkpath;

        # regular file
        if ($files->{$orig_file} eq '') {
            path($orig_file)->copy($new_fullname)
                or croak("Failed to copy $orig_file to $new_fullname\n");

            my $raw_mode = (stat ($orig_file))[2];
            my $mode_str = sprintf '%04o', $raw_mode & oct ('07777'); ## no critic (Bangs::ProhibitBitwiseOperators)
            chmod oct ($mode_str), $new_fullname;
        } else {
            my $new_symlink = $self->_rebase_build_to_output_dir($build_dir, $files->{$orig_file});
            {
                local $CWD = $new_fullname->parent;
                symlink $new_symlink, $new_fullname->basename;
            }
        }
    }

    path(PARCEL_METADATA_FILE())->spew_utf8(encode_json_pretty($package->spec));

    chdir '..';

    $log->infof('Creating parcel file for %s', $package->full_name);

    # The lovely thing here is that is creates a parcel file from the
    # bundled directory, which gets cleaned up automatically
    $self->parcel_repo->store_package_parcel($package, $parcel_dir_path);

    chdir $original_dir;

    return;
}

sub _rebase_build_to_output_dir {
    my ($self, $build_dir, $orig_filename) = @_;
    (my $new_filename = $orig_filename) =~ s/^ \Q$build_dir\E //xms;
    my @parts = File::Spec->splitdir($new_filename);

    # in case the path is absolute (leading slash)
    # the split function will generate an empty first element
    # if it's relative, it will have value and shouldn't be removed
    $parts[0] eq '' and shift @parts;

    return path(@parts);
}

__PACKAGE__->meta->make_immutable;

no Moose;

1;

__END__

=pod

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head2 config

See L<Pakket::Role::HasConfig>.

=head2 parcel_repo

See L<Pakket::Role::HasParcelRepo>.

=head1 METHODS

=head2 BUILD

Build phase, provided by L<Moose>, used to set up the parcel repo
before we begin bundling.

Do not call directly.

=head2 bundle($build_dir, $package, \%files)

This will bundle the list of files for a given package in a given
directory. It will create a parcel file which will include the files,
including metadata on the package it includes.

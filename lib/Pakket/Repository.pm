package Pakket::Repository;

# ABSTRACT: Build in-memory representation of repo

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

# core
use Archive::Tar;
use Errno qw(:POSIX);
use Module::Runtime qw(use_module);
use experimental qw(declared_refs refaliasing signatures);

# non core
use File::chdir;
use Path::Tiny;

# local
use Pakket::Helper::Versioner;
use Pakket::Type qw(PakketRepositoryBackend);
use Pakket::Utils::Package qw(
    parse_package_id
);

has 'type' => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
);

has 'backend' => (
    'is'      => 'ro',
    'does'    => 'PakketRepositoryBackend',
    'coerce'  => 1,
    'lazy'    => 1,
    'builder' => '_build_backend',
    'handles' => [qw(
            all_object_ids_by_name has_object remove
            retrieve_content retrieve_location
            store_content store_location
            ),
    ],
);

has 'all_objects_cache' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'lazy'    => 1,
    'builder' => '_build_all_objects_cache',
    'clearer' => 'clear_cache',
);

with qw(
    Pakket::Role::CanFilterRequirements
    Pakket::Role::HasLog
);

sub BUILD ($self, @) {
    $self->backend();
    return;
}

sub all_object_ids ($self) {
    my $ids = $self->backend->all_object_ids();
    $self->{'all_objects_cache'} = $self->_build_all_objects_cache($ids);
    return $ids;
}

sub retrieve_package_file ($self, $package) {
    my $id = $package->id;

    my $file = $self->retrieve_location($id)
        or $self->croakf('We do not have the %s for package %s', $self->type, $id);
    $self->log->tracef('fetched %s %s to %s', $self->type, $id, $file->stringify);

    my $dir = Path::Tiny->tempdir(
        'CLEANUP'  => 1,
        'TEMPLATE' => join ('', 'pakket-extract-', $package->name, '-XXXXXXXXXX'),
    );

    # Prefer system 'tar' instead of 'in perl' archive extractor, because 'tar' memory consumption is very low,
    # but perl extractor is really greed for memory and we got the error "Out of memory" on KVMs

    my $ae = use_module('Archive::Extract');
    ## no critic [Modules::RequireExplicitInclusion]
    $Archive::Extract::PREFER_BIN = 1;
    $Archive::Extract::PREFER_BIN
        or $self->croak('Incorrectly initialized Archive::Extract');

    my $arch = $ae->new(
        'archive' => $file->stringify,
        'type'    => 'tgz',
    );

    $arch->extract('to' => $dir)
        or $self->croakf(q{[%s] Unable to extract '%s' to '%s'}, $!, $file, $dir);
    $self->log->tracef('extracted %s %s to %s', $self->type, $id, $dir->stringify);

    return $dir;
}

sub freeze_location ($self, $orig_path) {
    my $base_path = $orig_path;

    my @files;
    if ($orig_path->is_file) {
        $base_path = $orig_path->basename;
        push (@files, $orig_path);
    } elsif ($orig_path->is_dir) {
        $orig_path->children
            or $self->croak('Cannot freeze empty directory:', $orig_path);

        $orig_path->visit(
            sub ($path, $) {
                $path->is_file
                    or return;
                push @files, $path;
            },
            {'recurse' => 1},
        );
    } else {
        $self->croak('Unknown location type:', $orig_path);
    }

    @files = map {$_->relative($base_path)->stringify} @files;

    # Write and compress
    my $arch = Archive::Tar->new();
    {
        local $CWD = $base_path; ## no critic [Variables::ProhibitLocalVars] chdir, to use relative paths in archive
        $arch->add_files(@files);
    }
    my $file = Path::Tiny->tempfile();
    $arch->write($file->stringify, COMPRESS_GZIP);

    return $file;
}

sub remove_package_file ($self, $package) {
    my $id = $package->id;

    if (not $self->has_object($id)) {
        $self->croakf('We do not have the %s for package %s', $self->type, $id);
    }

    $self->log->debugf('removing %s package %s', $self->type, $id);
    $self->remove($id);

    return;
}

sub latest_version_release ($self, $category, $name, $req_string) {
    $req_string ||= '>= 0';                                                    # explicitly convert '0' to '>= 0'

    my %types = (
        'perl'   => 'Perl',
        'native' => 'Perl',
    );

    my %versions;
    foreach my $object_id (@{$self->all_object_ids}) {
        my ($my_category, $my_name, $my_version, $my_release) = parse_package_id($object_id);

        $category eq $my_category and $name eq $my_name
            or next;

        push @{$versions{$my_version}}, $my_release;
    }

    my $versioner = Pakket::Helper::Versioner->new(
        'type' => $types{$category},
    );

    my $latest_version = $versioner->latest($category, $name, $req_string, keys %versions)
        or $self->croakf('Could not analyze %s/%s to find latest version', $category, $name);

    # return the latest version and latest release available for this version
    return [$latest_version, (sort @{$versions{$latest_version}})[-1]];
}

sub filter_requirements ($self, $requirements) {
    return $self->filter_packages_in_cache($requirements, $self->all_objects_cache);
}

sub filter_queries ($self, $queries) {                                         # returns only existing packages
    my %requirements = map {$_->short_name => $_} $queries->@*;
    my (\@found, undef) = $self->filter_packages_in_cache(\%requirements, $self->all_objects_cache);
    return @found;
}

sub select_available_packages ($self, $requirements, %params) {
    $requirements->%*
        or return [];

    $self->log->debugf('checking which packages are available in %s repo...', $self->type);
    my ($packages, $not_found) = $self->filter_packages_in_cache($requirements, $self->all_objects_cache);
    if ($not_found->@*) {
        foreach my $package ($not_found->@*) {
            my @available = $self->available_variants($self->all_objects_cache->{$package->short_name});
            $params{'silent'}
                or $self->log->warning(
                'Could not find package in',
                $self->type, 'repo:', $package->id, ('( available:', join (', ', @available), ')') x !!@available,
                );
        }

        my $msg = sprintf ('Unable to find amount of packages in repo: %d', scalar $not_found->@*);
        if ($params{'continue'}) {
            $params{'silent'}
                or $self->log->warn($msg);
        } else {
            local $! = ENOENT;
            $self->croak($msg);
        }
    }
    return $packages;
}

sub add_to_cache ($self, $short_name, $version, $release) {
    $self->all_objects_cache->{$short_name}{$version}{$release}++;
    return;
}

sub _build_all_objects_cache ($self, $ids = undef) {
    my %result;
    $ids //= $self->all_object_ids;
    foreach my $id ($ids->@*) {
        my ($category, $name, $version, $release) = parse_package_id($id);
        if ($category && $name && $version && $release) {
            $result{"${category}/${name}"}{$version}{$release}++;
        } else {
            $self->log->warn('Invalid id:', $id);
        }
    }
    return \%result;
}

sub _build_backend ($self) {
    $self->croak('Cannot create backend of generic type (using parameter or URI string)');
    return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 SYNOPSIS

    my $repository = Pakket::Repository::Spec->new(
        'backend' => Pakket::Repository::Backend::File->new(...),
    );

    # or
    my $repository = Pakket::Repository::Spec->new(
        'backend' => 'file:///var/lib/',
    );

    ...

This is an abstract class that represents all repositories. It
implements a few generic methods all repositories use. Other than that,
there is very little usage of instantiate this object.

Below is the documentation for these generic methods, as well as how to
set the backend when instantiating. If you are interested in
documentation about particular repository methods, see:

=over 4

=item * L<Pakket::Repository::Spec>

=item * L<Pakket::Repository::Source>

=item * L<Pakket::Repository::Parcel>

=back

=head1 ATTRIBUTES

=head2 backend

    my $repo = Pakket::Repository::Source->new(
        'backend' => Pakket::Repository::Backend::File->new(
            ...
        ),
    );

    # Or the short form:
    my $repo = Pakket::Repository::Source->new(
        'backed' => 'file://...',
    );

    # Or, if you need additional parameters
    my $repo = Pakket::Repository::Source->new(
        'backed'       => 'file://...',
        'backend_opts' => {
            'file_extension' => 'src',
        },
    );

You can either provide an object or a string URI. You can provide

Holds the repository backend implementation. Can be set with either an
object instance or with a string URI. Additional parameters can be set
with C<backend_opts>.

Existing backends are:

=over 4

=item * L<Pakket::Repository::Backend::File>

File-based backend, useful locally.

=item * L<Pakket::Repository::Backend::Http>

HTTP-based backend, useful remotely.

=item * L<Pakket::Repository::Backend::Dbi>

Database-based backed, useful remotely.

=back

=head2 backend_opts

A hash reference that holds any additional parameters that could either
be part of the URI specification (like a port) or extended beyond the
URI specification (like a file extension).

See examples in C<backend> above.

=head1 METHODS

=head2 retrieve_package_file

=head2 remove_package_file

=head2 freeze_location

=head2 all_object_ids

This method will call C<all_object_ids> on the backend.

=head2 all_object_ids_by_name

This method will call C<all_object_ids_by_name> on the backend.

=head2 has_object

This method will call C<has_object> on the backend.

=head2 store_content

This method will call C<store_content> on the backend.

=head2 retrieve_content

This method will call C<retrieve_content> on the backend.

=head2 store_location

This method will call C<store_location> on the backend.

=head2 retrieve_location

This method will call C<retrieve_location> on the backend.

=head2 remove

This method will call C<remove> on the backend.

=cut

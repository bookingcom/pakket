package Pakket::Controller::Put;

# ABSTRACT: Put packages, parcels and specs

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

# core
use Encode qw(decode);
use experimental qw(declared_refs refaliasing signatures);

# non core
use Module::Runtime qw(use_module);
use Path::Tiny;

# local
use Pakket::Type::Package;
use Pakket::Type::PackageQuery;
use Pakket::Utils qw(normalize_version);
use Types::Path::Tiny qw(Path AbsPath);

extends qw(Pakket::Controller::BaseRemoteOperation);

has 'path' => (
    'is'       => 'ro',
    'isa'      => Path,
    'coerce'   => 1,
    'required' => 1,
);

has [qw(overwrite ignore)] => (
    'is'      => 'ro',
    'isa'     => 'Int',
    'default' => 0,
);

sub execute ($self) {
    my $repo = $self->get_repo();

    my %files;
    if ($self->path->is_dir) {
        $self->path->visit(
            sub ($path, $) {
                $path->is_file
                    or return;

                my $relative = decode('UTF-8', $path->relative($self->path)->stringify, Encode::FB_CROAK);
                my $id       = $relative =~ s{[.] \w+ \z}{}xr;
                $files{$id} = $path;
            },
            {
                'follow_symlinks' => 0,
                'recurse'         => 1,
            },
        );
    } else {
        my ($query) = $self->queries->@*;

        $files{$query->id} = $self->path;
    }

    return $self->_process_files($repo, \%files);
}

sub _process_files ($self, $repo, $files_ref) {
    foreach my $id (sort keys $files_ref->%*) {
        my $query = Pakket::Type::PackageQuery->new_from_string($id,);

        if ($query->category eq 'perl' && $query->is_module()) {
            my $cpan = use_module('Pakket::Helper::Cpan')->new;
            $query->{'name'} = $cpan->determine_distribution($query->name);
            $query->clear_short_name;
        }

        $query->release
            or $self->croak('Release is required');

        my $package;
        if (my @found = $repo->filter_queries([$query])) {
            if ($self->ignore) {
                $self->log->info('Package already exists, ignoring:', $found[0]->id);
                next;
            }
            if ($self->overwrite) {
                $package = $found[0];
            } else {
                $self->croak('Package already exists:', $found[0]->id);
            }
        } else {
            my $version = $query->category eq 'native' ? $query->requirement : normalize_version($query->requirement)
                or $self->croak('Version is required');

            $package = Pakket::Type::Package->new(
                $query->%{qw(category name release)},
                'version' => $version,
            );
        }

        $self->log->info('Storing package', $id);
        $repo->store_location($id, $files_ref->{$id}->absolute->stringify);
    }

    return 0;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

package Pakket::Scaffolder::Native;
# ABSTRACT: Scffolding Native distributions

use Moose;
use MooseX::StrictConstructor;
use Path::Tiny          qw< path >;
use Log::Any            qw< $log >;

with qw<
    Pakket::Role::HasConfig
    Pakket::Role::HasSpecRepo
    Pakket::Role::HasSourceRepo
>;

has 'package' => (
    'is' => 'ro',
);

has 'source_archive' => (
    'is'      => 'ro',
    'isa'     => 'Maybe[Str]',
);

sub run {
    my $self = shift;

    if ( $self->spec_repo->has_object( $self->package->id ) ) {
        $log->debugf("Package %s already exists", $self->package->full_name);
        return;
    }

    $log->infof('Working on %s', $self->package->full_name);

    # Source
    $self->add_source();

    # Spec
    $self->add_spec();

    $log->infof('Done: %s', $self->package->full_name);
}

sub add_source {
    my $self = shift;

    if ($self->source_repo->has_object($self->package->id)) {
        $log->debugf("Package %s already exists in source repo (skipping)",
                        $self->package->full_name);
        return;
    }

    if (!$self->source_archive) {
        Carp::croak("Please specify --source-archive=<sources_file_name>");
    }

    my $file = path($self->source_archive);
    if (!$file->exists) {
        Carp::croak("Archive with sources doesn't exist: ", $self->source_archive);
    }

    my $target = Path::Tiny->tempdir();
    my $dir    = $self->unpack($target, $file);

    $log->debugf("Uploading %s into source repo from %s", $self->package->full_name, $dir);
    $self->source_repo->store_package_source($self->package, $dir);
}

sub add_spec {
    my $self = shift;

    $log->debugf("Creating spec for %s", $self->package->full_name);

    my $package = Pakket::Package->new(
            'category' => $self->package->category,
            'name'     => $self->package->name,
            'version'  => $self->package->version,
            'release'  => $self->package->release,
        );

    $self->spec_repo->store_package_spec($package);
}

sub unpack {
    my ($self, $target, $file) = @_;

    my $archive = Archive::Any->new($file);

    if ($archive->is_naughty) {
        Carp::croak($log->critical("Suspicious module ($file)"));
    }

    $archive->extract($target);

    my @files = $target->children();
    if (@files == 1 && $files[0]->is_dir) {
        return $files[0];
    }

    return $target;
}

__PACKAGE__->meta->make_immutable;
no Moose;
1;
__END__

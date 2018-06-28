package Pakket::Scaffolder::Native;
# ABSTRACT: Scffolding Native distributions

use Moose;
use MooseX::StrictConstructor;
use Path::Tiny          qw< path >;
use Log::Any            qw< $log >;

use Pakket::Downloader::ByUrl;

with qw<
    Pakket::Role::HasConfig
    Pakket::Role::HasSpecRepo
    Pakket::Role::HasSourceRepo
    Pakket::Role::CanApplyPatch
>;

has 'package' => (
    'is' => 'ro',
    'isa' => 'Pakket::PackageQuery',
    'required' => 1,
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

    return 0;
}

sub add_source {
    my $self = shift;

    if ($self->source_repo->has_object($self->package->id)) {
        $log->debugf("Package %s already exists in source repo (skipping)",
                        $self->package->full_name);
        return;
    }

    if (!$self->{package}{source}) {
        Carp::croak("Please specify --source-archive=<sources_file_name>");
    }

    my $download = Pakket::Downloader::ByUrl::create($self->{package}{name}, $self->{package}{source});
    my $dir      = $download->to_dir;
    $self->apply_patches($self->package, $dir);

    $log->debugf("Uploading %s into source repo from %s", $self->package->full_name, $dir);
    $self->source_repo->store_package_source($self->package, $dir);
}

sub add_spec {
    my $self = shift;

    $log->debugf("Creating spec for %s", $self->package->full_name);

    # we had PackageQuery in $package now convert it to Package
    my $package = Pakket::Package->new(%{$self->package});

    $self->spec_repo->store_package_spec($package);
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
__END__

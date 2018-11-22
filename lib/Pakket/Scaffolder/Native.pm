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
    my ($self) = @_;

    return if $self->is_package_in_spec_repo($self->{package}) and !$self->overwrite;

    return $self->_scaffold_package($self->package);
}

sub _scaffold_package {
    my ($self, $package) = @_;

    my $sources = $self->_fetch_source_for_package($package);

    $self->apply_patches($package, $sources);

    {
        local %ENV = %ENV; # keep all env changes locally
        if ($package->{manage}{env}) {
            foreach my $key (keys %{$package->{manage}{env}}) {
                $ENV{$key} = $package->{manage}{env}{$key};
            }
        }

        foreach my $cmd (@{ $package->{pre_manage} }) {
            my $ecode = system($cmd);
            Carp::croak("Unable to run '$cmd'") if $ecode;
        }
    }

    $log->infof('Working on %s', $package->full_name);
    $self->add_spec_for_package($package);
    $self->add_source_for_package($package, $sources);
    $log->infof('Done: %s', $package->full_name);
}

sub _fetch_source_for_package {
    my ($self, $package) = @_;

    my $download = Pakket::Downloader::ByUrl::create($package->name, $package->source);
    return $download->to_dir;
}

__PACKAGE__->meta->make_immutable;

no Moose;

1;
__END__

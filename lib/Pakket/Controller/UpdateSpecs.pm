package Pakket::Controller::UpdateSpecs;

# ABSTRACT: Update specs

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

# core
use Errno qw(:POSIX);
use Fatal qw(binmode);
use experimental qw(declared_refs refaliasing signatures switch);

# non core
use Module::Runtime qw(use_module);

# local
use Pakket::Type::Package;
use Pakket::Utils qw(clean_hash);

extends qw(Pakket::Controller::BaseRemoteOperation);

sub execute ($self) {
    my $ids = $self->spec_repo->all_object_ids;

    foreach my $id (sort $ids->@*) {
        my $spec    = $self->spec_repo->retrieve_package_by_id($id);
        my $package = Pakket::Type::Package->new_from_specdata($spec);

        #        if ($package->category eq 'perl') {
        #            #
        #        }
        $self->spec_repo->store_package($package, clean_hash($spec));
    }

    return 0;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

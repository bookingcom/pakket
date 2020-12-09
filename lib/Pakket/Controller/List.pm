package Pakket::Controller::List;

# ABSTRACT: List pakket packages

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

# core
use Carp qw(carp);
use version;
use experimental qw(declared_refs refaliasing signatures);

# non core
use Module::Runtime qw(use_module);
use JSON::MaybeXS qw(encode_json);

# local
use Pakket::Helper::Versioner;
use Pakket::Utils::Package qw(canonical_short_name);

has 'json' => (
    'is'      => 'ro',
    'default' => 0,
);

with qw(
    Pakket::Role::HasConfig
    Pakket::Role::HasInfoFile
    Pakket::Role::HasLibDir
    Pakket::Role::HasLog
    Pakket::Role::HasParcelRepo
    Pakket::Role::HasSourceRepo
    Pakket::Role::HasSpecRepo
);

## no critic [InputOutput::RequireBracedFileHandleWithPrint]

sub absent ($self) {
    my %spec_ids = map {$_ => 1} $self->spec_repo->all_object_ids()->@*;
    my %parc_ids = map {$_ => 1} $self->parcel_repo->all_object_ids()->@*;
    delete @spec_ids{keys (%parc_ids)};

    my @result = sort keys %spec_ids;

    return $self->_output(\@result);
}

sub installed ($self) {
    my \@result = $self->all_installed_packages();
    @result = sort @result;

    return $self->_output(\@result);
}

sub cpan_updates ($self) {
    my $cpan = use_module('Pakket::Helper::Cpan')->new;

    my \%outdated = $cpan->outdated($self->spec_repo->all_objects_cache());
    if ($self->json) {
        say encode_json([map {"$_=$outdated{$_}{'cpan_version'}"} sort keys %outdated]);
    } else {
        say "$_=$outdated{$_}{'version'} ($outdated{$_}{'cpan_version'})" foreach sort keys %outdated;
    }

    return 0;
}

sub updates ($self) {
    my $versioner  = Pakket::Helper::Versioner->new('type' => 'Perl');
    my \%installed = $self->all_installed_cache;
    my \%parcels   = $self->parcel_repo->all_objects_cache();

    my @result;
    foreach my $short_name (sort keys %installed) {
        if (exists $parcels{$short_name}) {
            my @versions            = keys $parcels{$short_name}->%*;
            my $latest_version      = $versioner->select_latest(\@versions);
            my ($latest_release)    = (reverse sort keys $parcels{$short_name}{$latest_version}->%*);
            my ($installed_version) = (keys $installed{$short_name}->%*);
            my ($installed_release) = (keys $installed{$short_name}{$installed_version}->%*);

            if (   $versioner->compare_version($installed_version, $latest_version) < 0
                || $installed_release ne $latest_release)
            {
                push (@result, canonical_short_name($short_name, $latest_version, $latest_release));
            }
        }

    }

    return $self->_output(\@result);
}

sub parcels ($self) {
    my @result = sort $self->parcel_repo->all_object_ids()->@*;

    return $self->_output(\@result);
}

sub sources ($self) {
    my @result = sort $self->source_repo->all_object_ids()->@*;

    return $self->_output(\@result);
}

sub specs ($self) {
    my @result = sort $self->spec_repo->all_object_ids()->@*;

    return $self->_output(\@result);
}

sub _output ($self, $result) {
    if ($self->json) {
        say encode_json($result);
    } else {
        say foreach $result->@*;
    }

    return 0;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

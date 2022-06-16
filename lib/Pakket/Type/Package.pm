package Pakket::Type::Package;

# ABSTRACT: An object representing a package

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

# core
use Carp;
use English      qw(-no_match_vars);
use experimental qw(declared_refs refaliasing signatures);

# non core
use Log::Any qw($log);

# local
use Pakket::Type::Meta;
use Pakket::Utils::Package qw(
    PAKKET_PACKAGE_STR
);
use Pakket::Utils qw(clean_hash normalize_version);

extends 'Pakket::Type::BasePackage';

with qw(
    Pakket::Type::Role::HasBasicPackageAttrs
    Pakket::Type::Role::HasMetaData
);

has [qw(version release)] => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
);

sub BUILD ($self, @) {
    $self->category eq 'perl'
        and $self->{'version'} = normalize_version($self->{'version'});

    $self->version
        or croak($log->critical('Invalid version:', $self->version));

    return;
}

sub new_from_string ($class, $id, %additional) {
    my $default_category = delete $additional{'default_category'};
    if ($id =~ PAKKET_PACKAGE_STR()) {
        return $class->new(
            'category' => $LAST_PAREN_MATCH{'category'} // $default_category,
            %LAST_PAREN_MATCH{qw(name version release)},
            %additional,
        );
    }
    croak($log->critical('Cannot parse:', $id));
}

sub new_from_specdata ($class, $spec, %additional) {
    return $class->new(
        $spec->{'Package'}->%*,
        'pakket_meta' => Pakket::Type::Meta->new_from_specdata($spec),
        %additional,
    );
}

sub spec ($self) {
    my %result = (
        'Package' => {$self->%{qw(category name version release source)}},
        $self->pakket_meta ? +('Pakket' => $self->pakket_meta->as_hash()) : (),
    );
    return clean_hash(\%result);
}

sub id ($self) {
    return Pakket::Utils::Package::canonical_name($self->category, $self->name, $self->version, $self->release);
}

sub variant ($self) {
    return Pakket::Utils::Package::short_variant($self->version, $self->release);
}

__PACKAGE__->meta->make_immutable;

1;

__END__

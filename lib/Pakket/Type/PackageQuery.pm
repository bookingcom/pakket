package Pakket::Type::PackageQuery;

# ABSTRACT: An object representing a query for a package

use v5.22;
use Moose;
use MooseX::Clone;
use MooseX::StrictConstructor;
use namespace::autoclean;

# core
use Carp;
use English qw(-no_match_vars);
use experimental qw(declared_refs refaliasing signatures);

# non core
use Log::Any qw($log);
use YAML;

# local
use Pakket::Type::Meta;
use Pakket::Type;
use Pakket::Utils qw(clean_hash);
use Pakket::Utils::Package qw(
    PAKKET_PACKAGE_STR
);

extends 'Pakket::Type::BasePackage';

with qw(
    MooseX::Clone
    Pakket::Role::CanVisitPrereqs
    Pakket::Type::Role::HasBasicPackageAttrs
    Pakket::Type::Role::HasConditions
    Pakket::Type::Role::HasMetaData
);

has 'version' => (
    'is'  => 'ro',
    'isa' => 'Maybe[Str]',
);

has 'release' => (
    'is'  => 'ro',
    'isa' => 'Maybe[Int]',
);

has [qw(release_info)] => (
    'is'  => 'ro',
    'isa' => 'Maybe[HashRef]',
);

sub BUILDARGS ($class, %args) {
    $args{'source'} && ref $args{'source'} eq 'ARRAY'
        and $args{'source'} = join ('', $args{'source'}->@*);
    $args{'requirement'} && $args{'requirement'} =~ m/:/
        and croak($log->critical('Bug in program, requirement has ":" in it', $args{'name'}, $args{'requirement'}));

    return \%args;
}

sub new_from_string ($class, $id, %additional) {
    my $default_category = delete $additional{'default_category'};
    if ($id =~ PAKKET_PACKAGE_STR()) {
        return $class->new(
            'category'    => $LAST_PAREN_MATCH{'category'} // $default_category,
            'name'        => $LAST_PAREN_MATCH{'name'},
            'requirement' => $LAST_PAREN_MATCH{'version'} // 0,
            ('release' => $LAST_PAREN_MATCH{'release'}) x !!$LAST_PAREN_MATCH{'release'},
            ('source'  => $additional{'source'}) x !!$additional{'source'},
            %additional,
        );
    }
    croak($log->critical('Cannot parse:', $id));
}

sub new_from_cpanfile ($class, $name, $requirement) {
    return $class->new(
        'category'    => 'perl',
        'name'        => $name,
        'requirement' => $requirement,
        'conditions'  => [determine_condition($requirement, 0)],
        'source'      => 'cpan',
    );
}

sub new_from_pakket_metafile ($class, $path, %additional) {
    my $data = Load($path->slurp_utf8);
    return $class->new(
        $data->%{qw(category name source)},
        ('requirement' => $data->{version}) x !!$data->{version},
        ('release'     => $data->{release}) x !!$data->{release},
        'pakket_meta' => Pakket::Type::Meta->new_from_metafile($path),
        %additional,
    );
}

sub inject_prereqs ($self, $prereqs) {
    if (my $meta = $self->pakket_meta) {
        $self->visit_prereqs(
            $meta->prereqs // {},
            sub ($phase, $type, $name, $requirement) {
                if ($requirement eq '-') {
                    delete $prereqs->{$phase}{$type}{$name};
                    return;
                }
                $prereqs->{$phase}{$type}{$name} = ($requirement || 0);
            },
        );
        $self->{'pakket_meta'} = $self->pakket_meta->clone(
            'prereqs' => clean_hash($prereqs),
        );
    } else {
        $self->{'pakket_meta'} = Pakket::Type::Meta->new_from_prereqs(clean_hash($prereqs));
    }
    return;
}

sub variant ($self) {
    return Pakket::Utils::Package::short_variant($self->version, $self->release);
}

__PACKAGE__->meta->make_immutable;

1;

__END__

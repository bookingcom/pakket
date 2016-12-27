package Pakket::Package;
# ABSTRACT: An object representing a package

use Moose;
use MooseX::StrictConstructor;
use Pakket::Utils qw< canonical_package_name >;

has 'name' => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
);

has 'category' => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
);

has 'version' => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
);

has [qw<build_opts bundle_opts>] => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'default' => sub { +{} },
);

has 'prereqs' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'default' => sub { return +{} },
);

# FIXME: GH #73 will make this more reasonable
has 'configure_prereqs' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'lazy'    => 1,
    'builder' => '_build_configure_prereqs',
);

has 'test_prereqs' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'lazy'    => 1,
    'builder' => '_build_test_prereqs',
);

has 'runtime_prereqs' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'lazy'    => 1,
    'builder' => '_build_runtime_prereqs',
);

sub _build_configure_prereqs {
    my $self    = shift;
    return $self->phase_prereqs('configure');
}

sub _build_test_prereqs {
    my $self    = shift;
    return $self->phase_prereqs('test');
}

sub _build_runtime_prereqs {
    my $self    = shift;
    return $self->phase_prereqs('runtime');
}

sub phase_prereqs {
    my ( $self, $phase ) = @_;
    my $prereqs = $self->prereqs;
    return +{
        map { $_ => $prereqs->{$_}{$phase} }
            keys %{$prereqs},
    };
}

sub cat_name {
    my $self = shift;

    return canonical_package_name( $self->category, $self->name );
}

sub full_name {
    my $self = shift;

    return canonical_package_name(
        $self->category, $self->name, $self->version,
    );
}

sub config {
    my $self = shift;

    return +{
        'Package' => {
            map +( $_ => $self->$_ ), qw<category name version>
        },

        'Prereqs' => $self->prereqs,

        map +( $_ => $self->$_ ), qw<build_opts bundle_opts>
    };
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

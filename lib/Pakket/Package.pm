package Pakket::Package;
# ABSTRACT: An object representing a package

use Moose;
use MooseX::StrictConstructor;

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
    return $self->category_prereqs('configure');
}

sub _build_test_prereqs {
    my $self    = shift;
    return $self->category_prereqs('test');
}

sub _build_runtime_prereqs {
    my $self    = shift;
    return $self->category_prereqs('runtime');
}

sub category_prereqs {
    my ( $self, $category ) = @_;
    my $prereqs = $self->prereqs;

    return [
        map +( $prereqs->{$category}{$_} ),
            keys %{ $prereqs->{$category} },
    ];
}

sub cat_name {
    my $self = shift;
    return sprintf '%s/%s', $self->category, $self->name;
}

sub full_name {
    my $self = shift;
    return sprintf '%s/%s=%s', $self->category, $self->name, $self->package;
}

sub config {
    my $self = shift;
    my @keys = qw<category name version prereqs build_opts bundle_opts>;

    return +{
        map +( $_ => $self->$_ ), @keys
    };
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

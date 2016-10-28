package Pakket::Package;
# ABSTRACT: An object representing a package

use Moose;
use MooseX::StrictConstructor;
use Module::Runtime qw< use_module >;

use constant {
    'VERSIONING_CLASSES' => {
        # Perl's versioning is likely to be a good default
        ''       => 'Pakket::Versioning::Default',
        'perl'   => 'Pakket::Versioning::Default',
        'native' => 'Pakket::Versioning::Default',
        'nodejs' => 'Pakket::Versioning::SemVer',
    },
};

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

has 'versioning' => (
    'is'        => 'ro',
    'isa'       => 'Str',
    'lazy'      => 1,
    'builder'   => '_build_versioning',

has [qw<build_opts bundle_opts>] => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'default' => sub { +{} },
);

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

has 'prereqs' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'default' => sub { return +{} },
);

sub _build_versioning {
    my $self     = shift;
    my $category = $self->category;

    exists VERSIONING_CLASSES()->{$category}
        and return VERSIONING_CLASSES()->{$category};

    return VERSIONING_CLASSES()->{''};
}

sub _build_configure_prereqs {
    my $self    = shift;
    return $self->_category_prereqs('configure');
}

sub _build_test_prereqs {
    my $self    = shift;
    return $self->_category_prereqs('test');
}

sub _build_runtime_prereqs {
    my $self    = shift;
    return $self->_category_prereqs('runtime');
}

sub _category_prereqs {
    my ( $self, $category ) = @_;
    my $prereqs = $self->prereqs;

    return [
        map +( $prereqs->{$_}{$category} ),
            keys %{$prereqs},
    ];
}

sub full_name {
    my $self = shift;
    return sprintf '%s/%s', $self->category, $self->name;
}

sub versioning_requirements {
    my $self       = shift;
    my $versioning = $self->versioning;

    return use_module($versioning)->new();
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

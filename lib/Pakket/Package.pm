package Pakket::Package;
# ABSTRACT: An object representing a package

use Moose;
use MooseX::StrictConstructor;
use Pakket::Types;
use Pakket::Constants qw< PAKKET_DEFAULT_RELEASE >;
use JSON::MaybeXS qw< decode_json >;
use version 0.77;

with qw< Pakket::Role::BasicPackageAttrs >;

has [ qw< name category version release > ] => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
);

has 'source' => (
    'is'       => 'ro',
    'isa'      => 'Maybe[Str]',
);

has 'is_bootstrap' => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'default' => sub {0},
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

sub BUILDARGS {
    my ( $class, %args ) = @_;
    if ($args{'category'} eq 'perl') {
        my $ver = version->new($args{'version'});
        if ($ver->is_qv) {$ver = version->new($ver->normal)};
        $args{'version'} = $ver->stringify();
    }
    return \%args;
}

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

sub spec {
    my $self = shift;

    my $result = {
        'Package' => {
            # This is so we don't see is_bootstrap in spec
            # if not required -- SX
            ( 'is_bootstrap' => 1 )x!! $self->is_bootstrap,

            map +( $_ => $self->$_ ), qw<category name version release>,
        },

        'Prereqs' => $self->prereqs,

        map +( $_ => $self->$_ ), qw<build_opts bundle_opts>,
    };
    $result->{Package}{source} = $self->{source} if $self->{source};

    return $result;
}

sub new_from_spec {
    my ( $class, $spec ) = @_;

    my %package_details = (
        %{ $spec->{'Package'} },
        'prereqs'      => $spec->{'Prereqs'}    || {},
        'build_opts'   => $spec->{'build_opts'} || {},
        'is_bootstrap' => !!$spec->{'is_bootstrap'},
    );

    return $class->new(%package_details);
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

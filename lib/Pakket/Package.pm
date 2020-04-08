package Pakket::Package;

# ABSTRACT: An object representing a package

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use Pakket::Types;
use Pakket::Constants qw< PAKKET_DEFAULT_RELEASE >;
use JSON::MaybeXS qw< decode_json >;
use version 0.77;

with qw< Pakket::Role::BasicPackageAttrs >;

has [qw< name category version release >] => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
);

has [qw<source distribution path>] => (
    'is'  => 'ro',
    'isa' => 'Maybe[Str]',
);

has [qw<patch pre_manage>] => (
    'is'  => 'ro',
    'isa' => 'Maybe[ArrayRef]',
);

has [qw<skip manage>] => (
    'is'  => 'ro',
    'isa' => 'Maybe[HashRef]',
);

has 'is_bootstrap' => (
    'is'  => 'ro',
    'isa' => 'Maybe[Bool]',
);

has [qw<build_opts bundle_opts>] => (
    'is'      => 'ro',
    'isa'     => 'Maybe[HashRef]',
    'default' => sub {{}},
);

has 'prereqs' => (
    'is'  => 'ro',
    'isa' => 'Maybe[HashRef]',
);

has 'as_prereq' => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'default' => sub {0},
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

sub BUILD {
    my $self = shift;

    if ($self->category eq 'perl') {
        my $ver = version->new($self->version);
        if ($ver->is_qv) {$ver = version->new($ver->normal)}
        $self->{version} = $ver->stringify();
    }
}

sub _build_configure_prereqs {
    my $self = shift;
    return $self->phase_prereqs('configure');
}

sub _build_test_prereqs {
    my $self = shift;
    return $self->phase_prereqs('test');
}

sub _build_runtime_prereqs {
    my $self = shift;
    return $self->phase_prereqs('runtime');
}

sub phase_prereqs {
    my ($self, $phase) = @_;
    my $prereqs = $self->prereqs;
    return +{
        map {$_ => $prereqs->{$_}{$phase}}
            keys %{$prereqs},
    };
}

sub spec {
    my $self = shift;

    my $result = {
        'Package' => {

            # This is so we don't see is_bootstrap in spec
            # if not required -- SX
            ('is_bootstrap' => 1) x !!$self->is_bootstrap,

            map +($_ => $self->$_), qw<category name version release>,
        },

        'Prereqs' => $self->prereqs,

        map +($_ => $self->$_),
        qw<build_opts bundle_opts>,
    };
    $self->$_ && $self->$_->%* and $result->{$_} = $self->$_ foreach qw(skip);
    $result->{Package}{source} = $self->{source} if $self->{source};

    return $result;
}

sub new_from_spec {
    my ($class, $spec) = @_;

    my %package_details = (
        %{$spec->{'Package'}},
        'prereqs'    => $spec->{'Prereqs'}    || {},
        'build_opts' => $spec->{'build_opts'} || {},
        'is_bootstrap' => !!$spec->{'is_bootstrap'},
    );

    $spec->{'skip'}
        and $package_details{'skip'} = $spec->{'skip'};

    return $class->new(%package_details);
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

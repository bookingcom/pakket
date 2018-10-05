package Pakket::PackageQuery;
# ABSTRACT: An object representing a query for a package

use Moose;
use MooseX::StrictConstructor;

use Carp              qw< croak >;
use Log::Any          qw< $log >;
use version 0.77;
use Pakket::Constants qw<
    PAKKET_PACKAGE_SPEC
    PAKKET_DEFAULT_RELEASE
>;
use Pakket::Types;

with qw< Pakket::Role::BasicPackageAttrs >;

has [qw< name category version >] => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
);

has 'release' => (
    'is'      => 'ro',
    'isa'     => 'PakketRelease',
    'coerce'  => 1,
    'default' => sub { PAKKET_DEFAULT_RELEASE() },
);

has [qw<distribution source url summary path>] => (
    'is'       => 'ro',
    'isa'      => 'Maybe[Str]',
);

has [qw<patch pre_manage>] => (
    'is'      => 'ro',
    'isa'     => 'Maybe[ArrayRef]',
);

has [qw<manage build_opts bundle_opts>] => (
    'is'      => 'ro',
    'isa'     => 'Maybe[HashRef]',
);

has 'prereqs' => (
    'is'      => 'ro',
    'isa'     => 'Maybe[HashRef]',
);

has 'skip' => (
    'is'      => 'ro',
    'isa'     => 'Maybe[HashRef]',
);

has 'is_bootstrap' => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'default' => sub {0},
);

sub BUILD {
    my $self = shift;

    # add supported categories
    if ( !( $self->category eq 'perl' or $self->category eq 'native' ) ) {
        croak( "Unsupported category: ${self->category}\n" );
    }
}

sub new_from_string {
    my ( $class, $req_str, $source ) = @_;

    if ( $req_str !~ PAKKET_PACKAGE_SPEC() ) {
        croak( $log->critical("Cannot parse $req_str") );
    } else {
        # This shuts up Perl::Critic
        return $class->new(
            'category' => $1,
            'name'     => $2,
            'version'  => $3 // 0,
            ('release' => $4)x!! $4,
            ('source'  => $source)x!! $source,
        );
    }
}

sub new_from_meta {
    my ( $class, $meta_spec ) = @_;

    my $params = { %$meta_spec{qw<category name version release source>} };

    $params->{patch}      = $meta_spec->{patch}        if $meta_spec->{patch};
    $params->{path}       = $meta_spec->{path}         if $meta_spec->{path};
    $params->{skip}       = $meta_spec->{skip}         if $meta_spec->{skip};
    $params->{manage}     = $meta_spec->{manage}       if $meta_spec->{manage};
    $params->{pre_manage} = $meta_spec->{'pre-manage'} if $meta_spec->{'pre-manage'};

    my $prereqs = _convert_requires($meta_spec);
    $params->{prereqs} = $prereqs if $prereqs;

    my $build_opts = _convert_build_options($meta_spec);
    foreach my $cmd (@{$meta_spec->{'pre-build'}}) {
        my @cmd_split = split(/\s/, $cmd);
        push(@{$build_opts->{pre_build}}, \@cmd_split);
    }
    foreach my $cmd (@{$meta_spec->{'post-build'}}) {
        my @cmd_split = split(/\s/, $cmd);
        push(@{$build_opts->{post_build}}, \@cmd_split);
    }
    $params->{build_opts} = $build_opts if $build_opts;

    return $class->new($params);
}

sub _convert_requires {
    my ($meta_spec) = @_;
    return unless $meta_spec->{requires};

    my $result = {};
    my $requires = $meta_spec->{requires};
    foreach my $type (keys %{$requires}) {
        foreach my $dep (@{$requires->{$type}}) {
            if ( $dep !~ PAKKET_PACKAGE_SPEC() ) {
                croak( $log->critical("Cannot parse requirement $dep") );
            } else {
                $result->{$1}{$type}{$2} = {version => $3 // 0};
            }
        }
    }
    return $result;
}

sub _convert_build_options {
    my ($meta_spec) = @_;
    my $opts = $meta_spec->{'build'};
    return unless $opts;

    my $result = {};
    $result->{env_vars}        = $opts->{env}                 if $opts->{env};
    $result->{configure_flags} = $opts->{'configure-options'} if $opts->{'configure-options'};
    $result->{build_flags}     = $opts->{'make-options'}      if $opts->{'make-options'};

    return $result;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

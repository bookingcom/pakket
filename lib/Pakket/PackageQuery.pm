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

has 'is_bootstrap' => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'default' => sub {0},
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

sub new_from_string {
    my ( $class, $req_str ) = @_;

    if ( $req_str !~ PAKKET_PACKAGE_SPEC() ) {
        croak( $log->critical("Cannot parse $req_str") );
    } else {
        # This shuts up Perl::Critic
        return $class->new(
            'category' => $1,
            'name'     => $2,
            'version'  => $3,
            ( 'release'  => $4 )x!! $4,
        );
    }
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

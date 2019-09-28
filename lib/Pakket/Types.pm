package Pakket::Types;
# ABSTRACT: Type definitions for Pakket

use v5.22;
use strict;
use warnings;

use Moose::Util::TypeConstraints;
use Carp     qw< croak >;
use Log::Any qw< $log >;
use Ref::Util qw< is_ref is_arrayref is_hashref >;
use Safe::Isa;
use Module::Runtime qw< require_module >;
use Pakket::Constants qw<
    PAKKET_DEFAULT_RELEASE
    PAKKET_VALID_PHASES
>;

# PakketRepositoryBackend

sub _coerce_backend_from_str {
    my $uri = shift;

    my ($scheme) = $uri =~ m{^ ( \w+ ) :// }xms;
    $scheme = lc($scheme);
    $scheme = 'http' if ($scheme eq 'https');
    my $class    = "Pakket::Repository::Backend::$scheme";

    eval { require_module($class); 1; } or do {
        croak( $log->critical("Failed to load backend '$class': $@") );
    };

    return $class->new_from_uri($uri);
}

sub _coerce_backend_from_arrayref {
    my $arrayref = shift;
    my ( $name, $data ) = @{$arrayref};
    $name = lc($name);
    $data //= {};

    # TODO: Remove that later.
    # For back compatibility with old config.
    if (!is_hashref($data)) {
        my ( $n, @params ) = @{$arrayref};
        $data = { @params };
    }

    is_hashref($data)
        or croak( $log->critical('Second arg to backend is not hashref') );

    my $class = "Pakket::Repository::Backend::$name";

    eval { require_module($class); 1; } or do {
        croak( $log->critical("Failed to load backend '$class': $@") );
    };

    return $class->new($data);
}

subtype 'PakketRepositoryBackend', as 'Object', where {
    $_->$_does('Pakket::Role::Repository::Backend')
        || is_arrayref($_)
        || ( !is_ref($_) && length )
}, message {
    'Must be a Pakket::Repository::Backend object or a URI string or arrayref'
};

coerce 'PakketRepositoryBackend', from 'Str',
    via { return _coerce_backend_from_str($_); };

coerce 'PakketRepositoryBackend', from 'ArrayRef',
    via { return _coerce_backend_from_arrayref($_); };

# PakketRelease

subtype 'PakketRelease', as 'Int';

coerce 'PakketRelease', from 'Undef',
    via { return PAKKET_DEFAULT_RELEASE() };

# PakketVersioning

subtype 'PakketVersioning', as 'Object',
where { $_->$_does('Pakket::Role::Versioning') };

coerce 'PakketVersioning', from 'Str',
via {
    my $type  = $_;
    my $class = "Pakket::Versioning::$type";

    eval {
        require_module($class);
        1;
    } or do {
        my $error = $@ || 'Zombie error';
        croak( $log->critical("Could not load versioning module ($type)") );
    };

    return $class->new();
};

# PakketPhase

enum 'PakketPhase' => [ keys %{PAKKET_VALID_PHASES()} ];

no Moose::Util::TypeConstraints;

1;

__END__

=pod

package Pakket::Types;
# ABSTRACT: Type definitions for Pakket

use strict;
use warnings;
use Moose::Util::TypeConstraints;
use Log::Any qw< $log >;
use Safe::Isa;
use Module::Runtime qw<require_module>;

sub _coerce_backend_from_arrayref {
    my $backend_data = shift;
    my ( $subclass, @args ) = @{$backend_data};
    my $class = "Pakket::Repository::Backend::$subclass";

    eval { require_module($class); 1; } or do {
        $log->critical("Failed to load backend '$class'");
        exit 1;
    };

    return $class->new(@args);
}

subtype 'PakketRepositoryBackend', as 'Object', where {
    $_->$_isa('ARRAY') || $_->$_does('Pakket::Role::Repository::Backend')
}, message {
    'Must be a Pakket::Repository::Backend object or an arrayref'
};

coerce 'PakketRepositoryBackend', from 'ArrayRef',
    via { return _coerce_backend_from_arrayref($_); };

no Moose::Util::TypeConstraints;

1;

__END__

=pod

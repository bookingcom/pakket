package Pakket::Role::HttpAgent;

# ABSTRACT: Role for Http requests

use v5.22;
use Moose::Role;
use namespace::autoclean;

# non core
use HTTP::Tiny;

has 'extract' => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'default' => 0,
);

has 'ua' => (
    'is'      => 'ro',
    'lazy'    => 1,
    'builder' => '_build_ua',
);

sub _build_ua {
    return HTTP::Tiny->new();
}

1;

__END__

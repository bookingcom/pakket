package Pakket::Scaffolder::Role::Backend;

# ABSTRACT: scaffolder: role for backend

use v5.22;
use Moose::Role;

use HTTP::Tiny;

requires 'run';

has extract => (
    is      => 'ro',
    isa     => 'Bool',
    default => 0,
);

has ua => (
    is      => 'ro',
    lazy    => 1,
    builder => '_build_ua',
);

sub _build_ua {
    return HTTP::Tiny->new();
}

no Moose::Role;
1;
__END__

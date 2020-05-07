package Pakket::Role::Versioner;

# ABSTRACT: A Versioning role

use v5.22;
use Moose::Role;
use namespace::autoclean;

requires qw(compare);

1;

__END__

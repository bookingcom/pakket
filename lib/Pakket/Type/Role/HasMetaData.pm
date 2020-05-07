package Pakket::Type::Role::HasMetaData;

# ABSTRACT: Provides spec metadata

use v5.22;
use Moose::Role;
use namespace::autoclean;

# core
use experimental qw(declared_refs refaliasing signatures);

# non core
use Pakket::Type::Meta;

has [qw(source)] => (
    'is'  => 'ro',
    'isa' => 'Maybe[Str]',
);

has 'pakket_meta' => (
    'is'        => 'ro',
    'isa'       => 'Maybe[Pakket::Type::Meta]',
    'predicate' => 'has_meta',
);

#has [qw(distribution path summary url)] => (
#'is'  => 'ro',
#'isa' => 'Maybe[Str]',
#);
#
#has [qw(patch pre_manage)] => (
#'is'  => 'ro',
#'isa' => 'Maybe[ArrayRef]',
#);
#
#has [qw(skip manage)] => (
#'is'  => 'ro',
#'isa' => 'Maybe[HashRef]',
#);
#
#has [qw(build_opts bundle_opts)] => (
#'is'  => 'ro',
#'isa' => 'Maybe[HashRef]',
#);
#
#has 'prereqs' => (
#'is'  => 'ro',
#'isa' => 'Maybe[HashRef]',
#);

#has 'my_meta' => (
#'is'  => 'ro',
#'isa' => 'Maybe[HashRef]',
#);

1;

__END__

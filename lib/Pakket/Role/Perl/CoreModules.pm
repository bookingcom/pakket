package Pakket::Role::Perl::CoreModules;

# ABSTRACT: Role Perl core modules support

use v5.22;
use Moose::Role;
use namespace::autoclean;

# core
use Module::CoreList;
use experimental qw(declared_refs refaliasing signatures);

sub list_core_modules {
    return \%Module::CoreList::upstream; ## no critic [Variables::ProhibitPackageVars]
}

sub should_skip_core_module ($name) {
    return Module::CoreList::is_core($name) && !${Module::CoreList::upstream}{$name};
}

1;

__END__

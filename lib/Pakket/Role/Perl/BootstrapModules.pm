package Pakket::Role::Perl::BootstrapModules;

# ABSTRACT: role to provide Perl's list of bootstrap modules (distributions)

use v5.22;
use Moose::Role;
use namespace::autoclean;

# hardcoded list of packages we have to build first using core modules to break cyclic dependencies.
# we have to maintain the order in order for packages to build this list is an arrayref to maintain order
has 'bootstrap_modules' => (
    'is'  => 'ro',
    'isa' => 'ArrayRef',
    'default' =>
        sub {['perl/ExtUtils-MakeMaker', 'perl/inc-latest', 'perl/Module-Build', 'perl/Module-Build-WithXSpp']},
);

1;

__END__

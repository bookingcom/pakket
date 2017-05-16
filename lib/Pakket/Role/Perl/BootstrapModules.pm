package Pakket::Role::Perl::BootstrapModules;
# ABSTRACT: role to provide Perl's list of bootstrap modules (distributions)

use Moose::Role;

# hardcoded list of packages we have to build first
# using core modules to break cyclic dependencies.
# we have to maintain the order in order for packages to build
has 'perl_bootstrap_modules' => (
    'is'      => 'ro',
    'isa'     => 'ArrayRef',
    'default' => sub {
        [qw<
            ExtUtils::MakeMaker
            Module::Build
            Module::Build::WithXSpp
        >]
    },
);

no Moose::Role;
1;
__END__

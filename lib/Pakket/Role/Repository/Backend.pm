package Pakket::Role::Repository::Backend;
# ABSTRACT: A role for all repository backends

use Moose::Role;

requires 'create_index';

no Moose::Role;

1;

__END__

=pod

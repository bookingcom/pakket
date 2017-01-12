package Pakket::Role::Repository::Backend;
# ABSTRACT: A role for all repository backends

use Moose::Role;

# These are helper methods we want the backend to implement
# in order for the Repository to easily use across any backend
requires qw< latest_version packages_list >;

no Moose::Role;

1;

__END__

=pod

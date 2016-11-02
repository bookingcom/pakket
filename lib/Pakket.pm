package Pakket;
# ABSTRACT: An Unopinionated Meta-Packaging System

use strict;
use warnings;

1;

__END__

=pod

=head1 DESCRIPTION

Pakket is a meta-packaging system that allows you to manage your system
dependencies. It works by trying to avoid work.

=head2 What can you do with Pakket?

=over 4

=item * You can represent packages closer to their true nature

Unlike most packaging systems, Pakket works to I<avoid> reducing the
complexity of packages. Instead of trying to take away what makes each
package unique, Pakket tries to make it possible for packages to retain
the information relevant to them.

One example of this is that different systems use different versioning
schemes, which can confuse packaging systems, not knowing which version
is older and which is newer.

Packages in Pakket can keep their version number, the way they see it.
That's just one example, though.

=item * You can connect different packages

Package systems designed specifically for, say Node.js, cannot connect
their packages with C dependencies or with Perl dependencies. C programs
do not have a packaging system, so C "packages" cannot be connected with
anything.

Because Pakket knows these packages, it can connect them together, even
if their own systems can't.

If you have a Perl binding to a C++ library, you can represent that
relationship in Pakket. Pakket will then know how to build the C++
library and build your Perl module binding to that C++ library.

=item * You can build packages for delivery

Pakket builds simple package files that can then be delivered to a
different machine and used there. While you I<should> use the Pakket
installer to deal with these packages, you can also open them up
yourself; no magic here.

=item * You can install packages

The Pakket installer allows installing a package and its dependencies
recursively, from disk or mirrors, and to manage your installation tree.

=item * Atomic installations, oh yeah

Did we mention all installations in Pakket are atomic? This means that
if you're installing 20 or 20,000 packages and it fails, everything
still works. Pakket only activates the new installation once it finished
everything.

=item * Reverts are also atomic, baby!

The Pakket installer allows, by default, to retain multiple
installation directories. This means any revert is simply a single
atomic operation of pointing to an older installation.

=item * Multiple instances

Most packaging systems can only work with a single installation of a
package for the entire system. If you need another copy of a package
(same version or a different version), you either can't do it, or the
packaging system must create a new package with a name that contains the
version (python27, python3, etc.).

Pakket considers any installation as a single installation instance. You
can have as many installations of a package as you want. There can be a
global one, a per-user one, a local directory one, a project-specific
want, etc.; your pick. You can use one or more than one.

=back

=head2 Pakket elements

Pakket has several key elements:

=head3 Packages

Every thing you wish to build and install is a package. A package
can be a program in your favorite language, a library of a language,
or anything at all. It will go through a build process you pick and
it will get bundled into a parcel.

=head3 Categories

All packages have a category. Unlike other systems, Pakket doesn't
have a flat structure of packages. They're split into categories.

The category of a package tells Pakket what kind of build system it
needs, how to retrieve metadata from the sources, and what to do
with it.

For example, packages in the B<perl> category tell Pakket that the
builder will need to use one of the available build systems for
a Perl module (such as C<ExtUtils::MakeMaker> or C<Module::Build>).
It will also use the versioning scheme that Perl has in order to
decide which is a newer version and which is older.

=head3 Requirements

Pakket makes a difference between a package and a requirement. A package
is an existing instance; a requirement is a description. The requirement
can have a range, for example.

=head3 Configuration files

Similar to RPM spec files, Pakket has configuration files. You can
create them yourself or you can use the
L<Pakket::CLI::Command::scaffold|scaffold> command to create them
for you.

The basic configuration file in Pakket contain a package's C<category>,
c<name>, and C<version>. It usually contains C<prereqs> as well,
keyed by the B<category> and the B<phase>. The phases can be
B<configure> (for build-time), B<test> (for when testing the build),
and B<runtime> (for using it).

At the moment Pakket keeps its configuration in TOML files.

An example of a configuration in Pakket:

    # perl/HTML-Tidy/1.56.toml:
    [Package]
    category = "perl"
    name = "HTML-Tidy"
    version = "1.56"
    [Prereqs.native.configure.tidyp]
    version = "1.04"
    [Prereqs.perl.configure.ExtUtils-MakeMaker]
    version = "7.24"
    [Prereqs.perl.runtime.Test-Simple]
    version = "1.302031"

The package details are in the C<Package> section. The prereqs are
in the C<Prereqs> section, under the C<native> or C<perl> categories,
under the C<configure> or C<runtime> phase.

=head3 Index

The B<index> is where Pakket maintains all known versions of every
package and their locations.

One of the abilities Pakket gives you is maintaining multiple "trees"
of systems, each needing different versions of each package.

=head3 Parcels

Parcels are the result of building packages. Parcels are what gets
finally installed.

While other packaging systems usually have I<development packages> (or
I<devel> or I<dev>), Pakket doesn't differentiate between those.
Instead, a Pakket package contains everything created at build time,
including the headers and the compiled results.


package Pakket;
# ABSTRACT: An Unopinionated Meta-Packaging System

use strict;
use warnings;

1;

__END__

=pod

=head1 DESCRIPTION

Pakket is a meta-packaging system that allows you to manage
dependencies. It works by trying to avoid work.

=head2 What can you do with Pakket?

The main purpose of Pakket is simple: Package applications and
libraries. That is all.

Pakket provides a lot of flexibility in how this is done. Here is a list
of specific things you can do with Pakket.

=over 4

=item * You can generate spec files automatically

Given an existing API for a language (Perl, Ruby, Python, Rust), Pakket
can generate the entire tree of configurations and all the dependencies
for a given language.

If you are looking to convert all your Perl modules, Pakket will simply
generate the appropriate specs and requirements.

=item * You can represent packages closer to their true nature

Arbitrary packaging systems (e.g., RPM, Deb, etc.) attempt to produce
the same packages as other more language-specific packaging systems
(Perl's CPAN, Ruby's Gem, Python's Pypi) by reducing the level of
detail each package provides.

Pakket doesn't do that. Pakket attempts to maintain as much information
from the source as it can in order to handle more complicated corner
cases.

An example of this is the way different systems compare versions. CPAN
and Gem and Pypi handle versions differently, but they are all reduces
for the general purpose that RPM or Deb provide.

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

=item * You can build packages for deployment

Pakket builds simple package files that can then be delivered to a
different machine and used there.

I mean, why else would we do this?

=item * You can install packages

The Pakket installer allows installing a package and its dependencies
recursively, from disk or mirrors, and to manage your installation tree.

Again, this is pretty mandatory.

=item * Atomic installations

Did we mention all installations in Pakket are atomic? This means that
if you're installing 20 or 20,000 packages and it fails, everything
still works. Pakket only activates the new installation once it finished
everything successfully.

=item * Reverts are also atomic

The Pakket installer allows, by default, to retain multiple
installation directories. This means any revert can be simply a single
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
one, etc.; your pick. You can use one or more than one.

=back

=head2 Pakket elements

Pakket has several key elements:

=head3 Packages

Everything you wish to build and install is a package. A package
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
can have a range of allowed versions for a package, for example.

=head3 Spec files

Similar to RPM spec files, Pakket has spec files. You can create them
yourself or you can use the L<generate|Pakket::CLI::Command::manage>
command to create them for you.

The basic spec file in Pakket contain a package's C<category>,
C<name>, and C<version>. It usually contains C<prereqs> as well,
keyed by the B<category> and the B<phase>. The phases can be
B<configure> (for build-time), B<test> (for when testing the build),
and B<runtime> (for using it).

An example of a spec in Pakket in JSON:

    {
       "Package" : {
          "category" : "perl",
          "name" : "HTML-Tidy",
          "version" : "1.56"
       },
       "Prereqs" : {
          "native" : {
             "configure" : {
                "tidyp" : {
                   "version" : "1.04"
                }
             }
          },
          "perl" : {
             "configure" : {
                "ExtUtils-MakeMaker" : {
                   "version" : "7.24"
                }
             },
             "runtime" : {
                "Test-Simple" : {
                   "version" : "1.302031"
                }
             }
          }
       }
    }

The package details are in the C<Package> section. The prereqs are
in the C<Prereqs> section, under the C<native> or C<perl> categories,
under the C<configure> or C<runtime> phase.

Pakket I<might> store these configurations in JSON, but it could also
store it in other ways if desired.

=head3 Parcels

Parcels are the result of building packages. Parcels are what gets
finally installed. You may also call them the "build artifacts" if you
wish.

While other packaging systems usually have I<development packages> (or
I<devel> or I<dev>), Pakket doesn't differentiate between those.
Instead, a Pakket package contains everything created at install time
for a built package, including the headers, if such would have been
installed.

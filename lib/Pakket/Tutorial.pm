package Pakket::Tutorial;

# ABSTRACT: A beginner's tutorial to Pakket

use v5.22;
use strict;
use warnings;

1;

__END__

=pod

=head1 Installing Pakket

First, you will need to install Pakket. There is more than one way to
do this.

Pakket uses Perl 5.22.2. While it is not required, we recommend having
it on local installations.

=head2 Install from CPAN

Once Pakket is released to CPAN, you could install it manually using
using L<cpan>, L<cpanm>, C<cpm>, or any other client.

    $ cpan Pakket
    # or
    $ cpanm Pakket
    # or
    $ cpm Pakket

=head2 Carton

=over 4

=item * Install C<Carton>

    $ cpan Carton
    # or
    $ cpanm Carton
    # or
    $ cpm Carton

=item * Clone the Pakket repo

    $ git clone https://github.com/xsawyerx/pakket.git

=item * Set up carton

    $ cd pakket
    $ carton

=back

To run pakket:

    carton exec perl -Ilib bin/pakket

=head2 Build it yourself

This is the preferred method for setting up a Pakket build machine. You
only need to have perl 5.10 and above. It will only be used for setting
up the initial environment.

Pakket provides a small one-file script which you can run in order to
build all of Pakket in one go. It doesn't need any dependencies at all,
other than perl 5.10 and above.

First, clone:

    $ git clone https://github.com/xsawyerx/pakket.git

Now build a self-contained instance of Pakket:

    $ cd pakket
    $ perl tools/seacan-pakket-packed.pl

(You may need to install openssl-devel as a dependency beforehand.)

This will download perl 5.22.2, all of the Perl dependencies Pakket
requires, and it will create a single tarball with everything put
together.

Inside there will be a small I<bin> file that runs everything
without using C<anything> from your system. Once you run this and build
everything, you can take this tarball into any machine and use Pakket
without even having perl installed.

Yes! This is an application that comes with everything included, even
the interpreter!

=head2 RPM or Deb package

This option is not yet available, but we intend to provide builds of
Pakket as either an C<.rpm> or C<.deb> packages.

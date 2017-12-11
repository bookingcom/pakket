package Pakket::Versioning::Perl;
# ABSTRACT: A Perl-style versioning class

use Moose;
use MooseX::StrictConstructor;
use version 0.77;

with qw< Pakket::Role::Versioning >;

sub compare {
    my ($ver1, $rel1) = split(/:/, $_[1]);
    my ($ver2, $rel2) = split(/:/, $_[2]);
    $rel1 //= 1;
    $rel2 //= 1;
    return (version->parse($ver1) <=> version->parse($ver2)
            or $rel1 <=> $rel2);
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

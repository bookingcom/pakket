package Pakket::Helper::Versioner::Perl;

# ABSTRACT: A Perl-style versioning class

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

# core
use experimental qw(declared_refs refaliasing signatures);
use version;

with qw(Pakket::Role::Versioner);

sub compare ($self, $req1, $req2) {
    my ($ver1, $rel1) = split (m/:/, $req1);
    my ($ver2, $rel2) = split (m/:/, $req2);
    $rel1 //= 1;
    $rel2 //= 1;
    return (version->parse($ver1) <=> version->parse($ver2) or $rel1 <=> $rel2);
}

sub compare_full ($ver1, $rel1, $ver2, $rel2) {
    $rel1 ||= 1;
    $rel2 ||= 1;
    return (version->parse($ver1) <=> version->parse($ver2) or $rel1 <=> $rel2);
}

__PACKAGE__->meta->make_immutable;

1;

__END__

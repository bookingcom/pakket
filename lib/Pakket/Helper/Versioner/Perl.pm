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

sub compare_version ($self, $ver1, $ver2) {
    return 0 if $ver1 eq $ver2;

    my $ver1_obj = eval {version->new($ver1)} || version->new(_permissive_filter($ver1));
    my $ver2_obj = eval {version->new($ver2)} || version->new(_permissive_filter($ver2));

    return $ver1_obj <=> $ver2_obj;
}

sub compare_full ($self, $ver1, $rel1, $ver2, $rel2) {
    $rel1 ||= 1;
    $rel2 ||= 1;
    return (version->parse($ver1) <=> version->parse($ver2) or $rel1 <=> $rel2);
}

sub _permissive_filter ($ver) {
    local $_ = $ver =~ s/^[Vv](\d)/$1/r;                                       # Bioinf V2.0
    s/^(\d+)_(\d+)$/$1.$2/;                                                    # VMS-IndexedFile 0_02
    s/-[[:alpha:]]+$//;                                                        # Math-Polygon-Tree 0.035-withoutworldwriteables
    s/([a-j])/ord($1)-ord('a')/gie;                                            # DBD-Solid 0.20a
    s/[_h-z-]/./gi;                                                            # makepp 1.50.2vs.070506
    s/\.{2,}/./g; ## no critic [RegularExpressions::ProhibitEscapedMetacharacters]
    s/^(\d+) + .+/$1/x;                                                        # Text-Format 0.52+NWrap0.11

    return $_;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

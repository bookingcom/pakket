package Pakket::Role::CanVisitPrereqs;

# ABSTRACT: A role providing prereqs filtering and processing support

use v5.22;
use Moose::Role;
use namespace::autoclean;

# core
use List::Util   qw(none);
use experimental qw(declared_refs refaliasing signatures);

sub visit_prereqs ($self, $prereqs, $code, %params) {
    my @result;
    foreach my $phase (qw(configure build runtime test develop)) {
        exists $prereqs->{$phase}
            or next;
        $params{'phases'} && none {$_ eq $phase} $params{'phases'}->@*
            and next;

        foreach my $type (qw(requires suggests recommends)) {
            exists $prereqs->{$phase}{$type}
                or next;
            $params{'types'} && none {$_ eq $type} $params{'types'}->@*
                and next;

            my \%p = $prereqs->{$phase}{$type};
            foreach my $module (sort keys %p) {
                push (@result, $code->($phase, $type, $module, $p{$module} || 0));
            }
        }
    }
    return \@result;
}

1;

__END__

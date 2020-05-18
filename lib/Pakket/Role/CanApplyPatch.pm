package Pakket::Role::CanApplyPatch;

# ABSTRACT: A role providing patching sources ability

use v5.22;
use Moose::Role;
use namespace::autoclean;

# core
use Carp;
use experimental qw(declared_refs refaliasing signatures);

# non core
use Path::Tiny;

sub apply_patches ($self, $query, $params) {
    $query->pakket_meta
        or return;

    my $meta    = $query->pakket_meta->scaffold // {};
    my $patches = $meta->{'patch'}
        or return;

    $self->log->info('Applying patches for:', $query->id);
    my $patches_path = $query->pakket_meta->{'path'}->parent->parent->child('patch', $query->name)->absolute;
    foreach my $patch ($patches->@*) {
        my $full_path
            = $patch =~ m{/}
            ? $patch
            : $patches_path->child($patch);
        $self->log->info('Patching with:', $full_path);
        my $cmd = "patch --no-backup-if-mismatch -p1 -sN -i $full_path -d " . $params->{'sources'}->absolute;
        system ($cmd) == 0
            or $self->log->croak('Unable to apply patch:', $cmd);
    }
    return;
}

1;

__END__

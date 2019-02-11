package Pakket::Role::CanApplyPatch;
# ABSTRACT: A role providing patching sources ability

use Moose::Role;
use Path::Tiny   qw< path >;
use Log::Any     qw< $log >;

sub apply_patches {
    my ($self, $package, $sources) = @_;

    return unless $package->{patch};

    $log->debugf("Applying some patches to $sources");
    foreach my $patch (@{$package->{patch}}) {
        unless ($patch =~ m/\//) {
            $patch = path($package->{path}, '../patch/'.$package->name, $patch)->absolute;
        }
        $log->debugf('Patching with ' . $patch);
        my $cmd = "patch --no-backup-if-mismatch -p1 -sN -i $patch -d " . $sources->absolute;
        my $ecode = system($cmd);
        Carp::croak("Unable to apply patch '$cmd'") if $ecode;
    }
}

no Moose::Role;

1;

__END__

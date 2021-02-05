package Pakket::Role::CanUninstallPackage;

# ABSTRACT: A role providing package uninstall functionality

use v5.22;
use Moose::Role;
use namespace::autoclean;

# core
use Carp;
use experimental qw(declared_refs refaliasing signatures);

# non core
use Path::Tiny;

sub uninstall_package ($self, $info_file, $package) {
    $self->log->debug('uninstalling package:', $package->id);
    my \%info = $self->remove_package_from_info_file($info_file, $package);

    my %parents;
    for my $file (sort $info{'files'}->@*) {
        my $path = $self->work_dir->child($file);

        $self->log->trace('deleting file:', $path);
        $path->exists && !$path->remove
            and $self->log->error("Could not remove $path: $!");

        $parents{$path->parent->absolute}++;
    }

    # remove parent dirs if there are no children
    foreach my $parent (map {path($_)} keys %parents) {
        while ($parent->exists && !$parent->children) {
            $self->log->trace('deleting  dir:', $parent);
            rmdir $parent
                or carp('Unable to rmdir');
            $parent = $parent->parent;
        }
    }

    return;
}

1;

__END__

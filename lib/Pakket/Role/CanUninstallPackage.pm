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
    my $info = delete $info_file->{'installed_packages'}{$package->category}{$package->name};

    for my $file (sort $info->{'files'}->@*) {
        $file =~ s{^files/}{}xms;                                              # (compatibility) remove 'files/' part from the begin of the path
        my $path = $self->work_dir->child($file);

        $self->log->trace('deleting file:', $path);
        $path->exists
            and !$path->remove
            and $self->log->error("Could not remove $path: $!");

        # remove parent dirs if there are no children
        my $parent = $path->parent;
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

package Pakket::Role::CanUninstallPackage;
# ABSTRACT: A role providing package uninstall functionality

use v5.22;
use Moose::Role;
use Path::Tiny   qw< path >;
use Log::Any     qw< $log >;

sub uninstall_package {
    my ( $self, $info_file, $package ) = @_;

    my $info = delete $info_file->{'installed_packages'}{$package->{'category'}}{$package->{'name'}};
    $log->debugf("Deleting package %s/%s", $package->{'category'}, $package->{'name'});

    for my $file ( sort @{ $info->{'files'} // [] } ) {
        delete $info_file->{'installed_files'}{$file};
        my ($file_name) = $file =~ m/\w+\/(.+)/;
        my $path = $self->work_dir->child($file_name);

        #$log->debugf( 'Deleting file %s', $path );
        $path->exists and !$path->remove and $log->error("Could not remove $path: $!");

        # remove parent dirs while there are no children
        my $parent = $path->parent;
        while ($parent->exists && (0 + $parent->children) == 0) {
            $log->debugf('Deleting dir %s', $parent);
            rmdir $parent;
            $parent = $parent->parent;
        }
    }
    return;
}

no Moose::Role;

1;

__END__

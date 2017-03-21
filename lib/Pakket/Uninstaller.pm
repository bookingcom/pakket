package Pakket::Uninstaller;

# ABSTRACT: Uninstall pakket packages

use Moose;
use MooseX::StrictConstructor;
use Path::Tiny qw< path  >;
use Types::Path::Tiny qw< Path  >;
use Log::Any qw< $log >;

use Pakket::Log;
use Pakket::LibDir;
use Pakket::InfoFile;

has 'lib_dir' => (
    'is'       => 'ro',
    'isa'      => Path,
    'coerce'   => 1,
    'required' => 1,
);

has 'packages' => (
    'is'       => 'ro',
    'isa'      => 'ArrayRef',
    'required' => 1,
);

has 'without_dependencies' => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'default' => 0,
);

sub get_list_of_packages_for_uninstall {
    my $self = shift;

    if ( !@{ $self->packages } ) {
        die $log->critical('Did not receive any packages to uninstall');
    }

    my $active_dir = Pakket::LibDir::get_active_dir( $self->lib_dir );
    my $info_file  = Pakket::InfoFile::load_info_file($active_dir);
    my @packages_for_uninstall
        = $self->get_packages_available_for_uninstall($info_file);

    return @packages_for_uninstall;
}

sub uninstall {
    my $self = shift;

    my $active_dir = Pakket::LibDir::get_active_dir( $self->lib_dir );
    my $info_file  = Pakket::InfoFile::load_info_file($active_dir);
    my @packages_for_uninstall
        = $self->get_packages_available_for_uninstall($info_file);
    unless ( 0 + @packages_for_uninstall ) {
        $log->notice("Don't have any packages for uninstall");
        return;
    }

    my $work_dir = Pakket::LibDir::create_new_work_dir( $self->lib_dir );

    foreach my $package (@packages_for_uninstall) {
        $self->delete_package( $work_dir, $info_file, $package );
    }

    Pakket::InfoFile::save_info_file( $work_dir, $info_file );
    Pakket::LibDir::activate_work_dir($work_dir);

    $log->infof(
        "Finished uninstalling %d packages from %s",
        0 + @packages_for_uninstall,
        $self->lib_dir
    );

    log_success(
        "Finished uninstalling:\n"
            . join( "\n",
            map { $_->{category} . "/" . $_->{name} }
                @packages_for_uninstall )
    );

    Pakket::LibDir::remove_old_libraries( $self->lib_dir );

    return;
}

sub get_packages_available_for_uninstall {
    my ( $self, $info_file ) = @_;

    # Algorithm
    # Walk through requested packages and their dependency tree and mark them 'to_delete'
    # Walk through all installed packages without 'to_delete' and their dependencies and mark them 'keep_it'
    # Remove all packages which have 'to_delete' and missing 'keep_it'
    #
    # Special case: throw an error if user explicitly wants to remove packages ('delete_by_requirements'),
    # but that packages is required by any packages from the list 'keep_it.

    #mark packages for uninstall as 'to_delete' and 'to_delete_by_requerement'
    my $installed_packages = $info_file->{'installed_packages'};
    my @queue;
    my ( %to_delete, %to_delete_by_requirements );
    foreach my $package ( @{ $self->packages } ) {
        if ( !$installed_packages->{ $package->{category} }
            { $package->{name} } )
        {
            die $log->critical(
                "Package $package->{category}/$package->{name} doesn't exists"
            );
        }
        $to_delete{ $package->{category} }{ $package->{name} }++ and next;
        push @queue, $package;
        $to_delete_by_requirements{ $package->{category} }
            { $package->{name} }++;
    }

    # walk through dependencies and mark them as 'to delete'
    if ( !$self->without_dependencies ) {
        while ( 0 + @queue ) {
            my $package  = shift @queue;
            my $prereqs = $installed_packages->{ $package->{category} }
                { $package->{name} }{'prereqs'};
            for my $category ( keys %$prereqs ) {
                for my $type ( keys %{ $prereqs->{$category} } ) {
                    for my $name ( keys %{ $prereqs->{$category}{$type} } ) {
                        $to_delete{$category}{$name}++ and next;
                        push @queue,
                            { 'category' => $category, 'name' => $name };
                    }
                }
            }
        }
    }

    #select all package without 'to_delete' and mark them and theirs dependencies as 'keep_it'
    my %keep_it;
    foreach my $category ( keys %$installed_packages ) {
        foreach my $name ( keys %{ $installed_packages->{$category} } ) {
            $to_delete{$category}{$name} and next;
            $keep_it{$category}{$name}++ and next;

            # walk through dependencies
            @queue = ( { category => $category, name => $name } );
            while ( 0 + @queue ) {
                my $package  = shift @queue;
                my $prereqs = $installed_packages->{ $package->{category} }
                    { $package->{name} }{'prereqs'};
                for my $category ( keys %$prereqs ) {
                    for my $type ( keys %{ $prereqs->{$category} } ) {
                        for my $name (
                            keys %{ $prereqs->{$category}{$type} } )
                        {
                            $keep_it{$category}{$name}++ and next;
                            $to_delete_by_requirements{$category}{$name}
                                and die $log->critical(
                                "Can't uninstall package $category/$name, it's requered by $package->{category}/$package->{name}"
                                );
                            push @queue,
                                { 'category' => $category, 'name' => $name };
                            delete $to_delete{$category}{$name};
                        }
                    }
                }
            }
        }
    }

    my @packages_for_uninstall;
    for my $category ( keys %to_delete ) {
        for my $name ( keys %{ $to_delete{$category} } ) {
            push @packages_for_uninstall,
                { 'category' => $category, 'name' => $name };
        }
    }
    return @packages_for_uninstall;
}

sub delete_package {
    my ( $self, $work_dir, $info_file, $package ) = @_;
    my $info = delete $info_file->{installed_packages}{ $package->{category} }
        { $package->{name} };
    $log->debugf( "Deleting package %s/%s",
        $package->{category}, $package->{name} );

    for my $file ( @{ $info->{files} } ) {
        delete $info_file->{installed_files}{$file};
        my ( $type, $file_name ) = $file =~ /(\w+)\/(.+)/;
        my $path = $work_dir->child($file_name);
        $log->debugf( "Deleting file %s", $path );
        if ( !$path->remove ) {
            $log->error("Could not remove $path: $!");
        }

        # remove parent dirs while there are no children
        my $parent = $path->parent;
        while ( !( 0 + $parent->children ) ) {
            $log->debugf( "Deleting directory %s", $parent );
            rmdir $parent;
            $parent = $parent->parent;
        }

    }
    return;
}

__PACKAGE__->meta->make_immutable;

no Moose;

1;

__END__

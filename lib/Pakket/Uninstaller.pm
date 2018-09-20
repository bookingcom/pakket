package Pakket::Uninstaller;

# ABSTRACT: Uninstall pakket packages

use Moose;
use MooseX::StrictConstructor;
use Carp qw< croak >;
use Path::Tiny qw< path  >;
use Types::Path::Tiny qw< Path  >;
use Log::Any qw< $log >;

use Pakket::Log qw< log_success log_fail >;

with qw<
    Pakket::Role::HasInfoFile
    Pakket::Role::HasLibDir
>;

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

    @{ $self->packages }
        or croak( $log->critical('Did not receive any packages to uninstall') );

    my $info_file  = $self->load_info_file($self->active_dir);
    my @packages_for_uninstall
        = $self->get_packages_available_for_uninstall($info_file);

    return @packages_for_uninstall;
}

sub uninstall {
    my $self = shift;

    my $info_file  = $self->load_info_file($self->active_dir);
    my @packages_for_uninstall
        = $self->get_packages_available_for_uninstall($info_file);
    unless ( 0 + @packages_for_uninstall ) {
        $log->notice("Don't have any packages for uninstall");
        return;
    }

    foreach my $package (@packages_for_uninstall) {
        $self->delete_package( $info_file, $package );
    }

    $self->save_info_file( $self->work_dir, $info_file );
    $self->set_rollback_tag($self->work_dir, $self->rollback_tag);
    $self->activate_work_dir;

    $log->infof(
        "Finished uninstalling %d packages from %s",
        0 + @packages_for_uninstall,
        $self->pakket_dir
    );

    log_success(
        "Finished uninstalling:\n"
            . join( "\n",
            map { $_->{category} . "/" . $_->{name} }
                @packages_for_uninstall )
    );

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
        $installed_packages->{ $package->{category} }{ $package->{name} }
            or croak( $log->critical(
                "Package $package->{category}/$package->{name} doesn't exists"
            ) );

        $to_delete{ $package->{category} }{ $package->{name} }++ and next;
        push @queue, $package;
        $to_delete_by_requirements{ $package->{category} }
            { $package->{name} }++;
    }

    # walk through dependencies and mark them as 'to delete'
    if ( !$self->without_dependencies ) {
        while ( 0 + @queue ) {
            my $package  = shift @queue;
            my $category = $package->{'category'};
            my $name = $package->{'name'};
            exists $installed_packages->{$category}
                and exists $installed_packages->{$category}{$name}
                    or next;

            my $prereqs = $installed_packages->{$category}{$name}{'prereqs'};

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
                my $pr_category = $package->{'category'};
                my $pr_name = $package->{'name'};

                exists $installed_packages->{$pr_category}
                    and exists $installed_packages->{$pr_category}{$pr_name}
                        or next;

                my $prereqs = $installed_packages->{$pr_category}
                                                    ->{$pr_name}{'prereqs'};

                for my $category ( keys %$prereqs ) {
                    for my $type ( keys %{ $prereqs->{$category} } ) {
                        for my $name (
                            keys %{ $prereqs->{$category}{$type} } )
                        {
                            $keep_it{$category}{$name}++ and next;
                            $to_delete_by_requirements{$category}{$name}
                                and croak( $log->critical(
                                    "Can't uninstall package $category/$name, "
                                   . "it's required by $pr_category/$pr_name"
                                ));
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
    my ( $self, $info_file, $package ) = @_;
    my $info = delete $info_file->{installed_packages}{ $package->{category} }
        { $package->{name} };
    $log->debugf( "Deleting package %s/%s",
        $package->{category}, $package->{name} );

    for my $file ( sort @{ $info->{files} // [] } ) {
        delete $info_file->{installed_files}{$file};
        my ($file_name) = $file =~ /\w+\/(.+)/;
        my $path = $self->work_dir->child($file_name);
        $log->debugf( "Deleting file %s", $path );
        $path->exists and !$path->remove
            and $log->error("Could not remove $path: $!");

        # remove parent dirs while there are no children
        my $parent = $path->parent;
        while ($parent->exists && (0 + $parent->children) == 0) {
            $log->debugf("Deleting dir  %s", $parent);
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

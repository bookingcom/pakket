package Pakket::Role::HasInfoFile;
# ABSTRACT: Functions to work with 'info.json'

use v5.22;
use Moose::Role;

use Log::Any qw< $log >;
use JSON::MaybeXS qw< decode_json >;
use Pakket::Utils qw< encode_json_pretty >;
use Pakket::Constants qw<PAKKET_INFO_FILE>;
use Pakket::Package;

sub add_package_to_info_file {
    my ( $self, $parcel_dir, $install_data, $package, $opts ) = @_;

    my %files;

    # get list of files
    $parcel_dir->visit(
        sub {
            my ( $path, $state ) = @_;
            $path->is_file or return;

            my $filename = $path->relative($parcel_dir);
            $files{$filename} = {
                'category' => $package->category,
                'name'     => $package->name,
                'version'  => $package->version,
                'release'  => $package->release,
            };
        },
        { 'recurse' => 1 },
    );

    my ( $cat, $name ) = ( $package->category, $package->name );
    $install_data->{'installed_packages'}{$cat}{$name} = {
        'version'   => $package->version,
        'release'   => $package->release,
        'files'     => [ sort keys %files ],
        'as_prereq' => $opts->{'as_prereq'} ? 1 : 0,
        'prereqs'   => $package->prereqs,
    };

    foreach my $file ( keys %files ) {
        $install_data->{'installed_files'}{$file} = $files{$file};
    }
}

sub set_rollback_tag {
    my ( $self, $dir, $tag ) = @_;

    my $install_data = $self->load_info_file($dir);

    $install_data->{rollback_tag} = $tag;

    $self->save_info_file( $dir, $install_data );
}

sub get_rollback_tag {
    my ( $self, $dir ) = @_;

    my $install_data = $self->load_info_file($dir);

    return $install_data->{rollback_tag} // '';
}

sub load_info_file {
    my ($self, $dir) = @_;

    my $info_file = $dir->child( PAKKET_INFO_FILE() );

    my $install_data
        = $info_file->exists
        ? decode_json( $info_file->slurp_utf8 )
        : {};

    return $install_data;
}

sub save_info_file {
    my ( $self, $dir, $install_data ) = @_;

    my $info_file = $dir->child( PAKKET_INFO_FILE() );

    $info_file->spew_utf8( encode_json_pretty($install_data) );
}

sub load_installed_packages {
    my ($self, $dir) = @_;

    my $install_data = $self->load_info_file($dir);
    my $packages = $install_data->{'installed_packages'};
    my %result = ();
    for my $category (keys %$packages) {
        for my $name (keys %{$packages->{$category}}) {
            my $p = $packages->{$category}{$name};
            my $package = Pakket::Package->new(
                                'category' => $category,
                                'name'     => $name,
                                'version'  => $p->{'version'},
                                'release'  => $p->{'release'},
                            );
            $result{$package->short_name} = $package;
        }
    }
    return \%result;
}

no Moose::Role;
1;
__END__

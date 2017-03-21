package Pakket::InfoFile;

# ABSTRACT: Functions to work with 'info.json'

use Log::Any qw< $log >;
use JSON::MaybeXS qw< decode_json >;
use Pakket::Utils qw< encode_json_pretty >;
use Pakket::Constants qw<PAKKET_INFO_FILE>;

sub add_package {
    my ( $parcel_dir, $dir, $package, $opts ) = @_;

    my $prereqs      = $package->prereqs;
    my $install_data = load_info_file($dir);

    my %files;

    # get list of files
    $parcel_dir->visit(
        sub {
            my ( $path, $state ) = @_;

            $path->is_file
                or return;

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
        'files'     => [ keys %files ],
        'as_prereq' => $opts->{'as_prereq'} ? 1 : 0,
        'prereqs'   => $package->prereqs,
    };

    foreach my $file ( keys %files ) {
        $install_data->{'installed_files'}{$file} = $files{$file};
    }

    save_info_file( $dir, $install_data );
}

sub load_info_file {
    my $dir = shift;

    my $info_file = $dir->child( PAKKET_INFO_FILE() );

    my $install_data
        = $info_file->exists
        ? decode_json( $info_file->slurp_utf8 )
        : {};

    return $install_data;
}

sub save_info_file {
    my ( $dir, $install_data ) = @_;

    my $info_file = $dir->child( PAKKET_INFO_FILE() );

    $info_file->spew_utf8( encode_json_pretty($install_data) );
}

1;

__END__

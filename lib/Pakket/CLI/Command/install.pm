package Pakket::CLI::Command::install;
# ABSTRACT: The pakket install command

use strict;
use warnings;
use Pakket::CLI '-command';
use Pakket::Installer;
use Pakket::Config;
use Pakket::Log;
use Pakket::Package;
use Pakket::Constants qw< PAKKET_PACKAGE_SPEC >;
use Log::Any::Adapter;
use Path::Tiny      qw< path >;

sub abstract    { 'Install a package' }
sub description { 'Install a package' }

sub _determine_config {
    my ( $self, $opt ) = @_;

    # Read configuration
    my $config_file   = $opt->{'config'};
    my $config_reader = Pakket::Config->new(
        $config_file ? ( 'files' => [$config_file] ) : (),
    );

    my $config = $config_reader->read_config;

    # Default File backend
    if ( $opt->{'from'} ) {
        $config->{'repositories'}{'parcel'} = [
            'File', 'directory' => $opt->{'from'},
        ];
    }

    # Double check
    if ( !$config->{'repositories'}{'parcel'} ) {
        $self->usage_error(
            "Missing where to install\n"
          . '(Create a configuration or use --from)',
        );
    }

    return $config;
}

sub _determine_packages {
    my ( $self, $opt, $args ) = @_;

    my @package_strs
        = defined $opt->{'input_file'}
        ? path( $opt->{'input_file'} )->lines_utf8( { 'chomp' => 1 } )
        : @{$args};

    my @packages;
    foreach my $package_str (@package_strs) {
        my ( $pkg_cat, $pkg_name, $pkg_version, $pkg_release ) =
            $package_str =~ PAKKET_PACKAGE_SPEC();

        if ( !defined $pkg_version || !defined $pkg_release ) {
            $self->usage_error(
                'Currently you must provide a version and release to install: '
                .  $package_str,
            );
        }

        push @packages, Pakket::Package->new(
            'category' => $pkg_cat,
            'name'     => $pkg_name,
            'version'  => $pkg_version,
            'release'  => $pkg_release,
        );
    }

    return \@packages;
}

sub opt_spec {
    return (
        [
            'to=s',
            'directory to install the package in',
            { 'required' => 1 },
        ],
        [
            'from=s',
            'directory to install the packages from',
        ],
        [ 'input-file=s', 'install eveything listed in this file' ],
        [ 'config|c=s',   'configuration file' ],
        [ 'show-installed', 'print list of installed packages' ],
        [
            'verbose|v+',
            'verbose output (can be provided multiple times)',
            { 'default' => 1 },
        ],
    );
}

sub validate_args {
    my ( $self, $opt, $args ) = @_;

    Log::Any::Adapter->set( 'Dispatch',
        'dispatcher' => Pakket::Log->build_logger( $opt->{'verbose'} ) );

    $opt->{'pakket_dir'} = $opt->{'to'};
    $opt->{'config'}     = $self->_determine_config($opt);
    $opt->{'packages'}   = $self->_determine_packages( $opt, $args );

    $opt->{'config'}{'env'}{'cli'} = 1;
}

sub execute {
    my ( $self, $opt ) = @_;

    my $installer = Pakket::Installer->new(
        'config'     => $opt->{'config'},
        'pakket_dir' => $opt->{'pakket_dir'},
    );

    $opt->{'show_installed'}
        and return $installer->show_installed();

    return $installer->install( @{ $opt->{'packages'} } );
}

1;

__END__

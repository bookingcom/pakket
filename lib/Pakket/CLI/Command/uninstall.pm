package Pakket::CLI::Command::uninstall;

# ABSTRACT: The pakket uninstall command

use strict;
use warnings;

use Log::Any qw< $log >;
use Log::Any::Adapter;
use IO::Prompt::Tiny qw< prompt >;
use Path::Tiny qw< path >;

use Pakket::CLI '-command';
use Pakket::Config;
use Pakket::Uninstaller;
use Pakket::Log;
use Pakket::Package;
use Pakket::Constants qw< PAKKET_PACKAGE_SPEC >;

sub abstract    {'Uninstall a package'}
sub description {'Uninstall a package'}

sub _determine_packages {
    my ( $self, $opt, $args ) = @_;

    my @package_strs
        = defined $opt->{'input_file'}
        ? path( $opt->{'input_file'} )->lines_utf8( { 'chomp' => 1 } )
        : @{$args};

    my @packages;
    foreach my $package_str (@package_strs) {
        my ( $pkg_cat, $pkg_name ) = $package_str =~ PAKKET_PACKAGE_SPEC();

        if ( !$pkg_cat || !$pkg_name ) {
            die $log->critical(
                "Can't parse $package_str. Use format category/package_name");
        }

        push @packages, { 'category' => $pkg_cat, 'name' => $pkg_name };
    }

    return \@packages;
}

sub _determine_config {
    my ( $self, $opt ) = @_;

    # Read configuration
    my $config_file   = $opt->{'config'};
    my $config_reader = Pakket::Config->new(
        $config_file ? ( 'files' => [$config_file] ) : (),
    );

    my $config = $config_reader->read_config;

    if ( $opt->{'pakket_dir'} ) {
        $config->{'install_dir'} = $opt->{'pakket_dir'};
    }

    if ( !$config->{'install_dir'} ) {
        $self->usage_error(
            "please define the library dir --pakket-dir <path_to_library>\n"
        );
    }

    path($config->{'install_dir'})->exists
        or $self->usage_error( sprintf(
            "Library dir: %s doesn't exist\n", $config->{'install_dir'}));

    return $config;
}

sub opt_spec {
    return (
        [ 'pakket-dir=s',         'path where installed pakket' ],
        [ 'input-file=s',         'uninstall everything listed in this file' ],
        [ 'without-dependencies', 'don\'t remove dependencies' ],
        [
            'verbose|v+',
            'verbose output (can be provided multiple times)',
        ],
    );
}

sub validate_args {
    my ( $self, $opt, $args ) = @_;

    Log::Any::Adapter->set( 'Dispatch',
        'dispatcher' => Pakket::Log->build_logger( $opt->{'verbose'} ) );

    $opt->{'config'}   = $self->_determine_config($opt);
    $opt->{'packages'} = $self->_determine_packages( $opt, $args );
}

sub execute {
    my ( $self, $opt ) = @_;

    my $uninstaller = Pakket::Uninstaller->new(
        'pakket_dir'           => $opt->{'config'}{'install_dir'},
        'packages'             => $opt->{'packages'},
        'without_dependencies' => $opt->{'without_dependencies'},
    );

    my @packages_for_uninstall
        = $uninstaller->get_list_of_packages_for_uninstall();

    print "We are going to remove:\n";
    for my $package (@packages_for_uninstall) {
        print "* $package->{category}/$package->{name}\n";
    }

    my $answer = prompt( 'Continue?', 'y' );

    lc $answer eq 'y'
        and $uninstaller->uninstall();

    return;
}

1;

__END__

=pod

=head1 SYNOPSIS

    $ pakket uninstall perl/Dancer2

=head1 DESCRIPTION

Uninstall a given package.

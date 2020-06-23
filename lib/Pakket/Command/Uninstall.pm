package Pakket::Command::Uninstall;

# ABSTRACT: The pakket uninstall command

use v5.22;
use strict;
use warnings;
use namespace::autoclean;

use Carp;
use Log::Any qw($log);
use Log::Any::Adapter;
use IO::Prompt::Tiny qw(prompt);
use Path::Tiny;
use Module::Runtime qw(use_module);

use Pakket '-command';
use Pakket::Utils::Package qw(
    parse_package_id
);

sub abstract {
    return 'Uninstall a package';
}

sub description {
    return 'Uninstall a package';
}

sub _determine_packages {
    my ($self, $opt, $args) = @_;

    my @package_strs
        = defined $opt->{'input_file'}
        ? path($opt->{'input_file'})->lines_utf8({'chomp' => 1})
        : @{$args};

    my @packages;
    foreach my $package_str (@package_strs) {
        my ($pkg_cat, $pkg_name) = parse_package_id($package_str);

        if (!$pkg_cat || !$pkg_name) {
            croak($log->critical("Can't parse $package_str. Use format category/package_name"));
        }

        push @packages,
            {
            'category' => $pkg_cat,
            'name'     => $pkg_name,
            };
    }

    return \@packages;
}

sub _determine_config {
    my ($self, $opt) = @_;

    # Read configuration
    my $config_file   = $opt->{'config'};
    my $config_reader = use_module('Pakket::Config')->new($config_file ? ('files' => [$config_file]) : ());

    my $config = $config_reader->read_config;

    if ($opt->{'pakket_dir'}) {
        $config->{'install_dir'} = $opt->{'pakket_dir'};
    }

    if (!$config->{'install_dir'}) {
        $self->usage_error("please define the library dir --pakket-dir <path_to_library>\n");
    }

    path($config->{'install_dir'})->exists
        or $self->usage_error(sprintf ("Library dir: %s doesn't exist\n", $config->{'install_dir'}));

    return $config;
}

sub opt_spec {
    return (
        ['pakket-dir=s',         'path where installed pakket'],
        ['input-file=s',         'uninstall everything listed in this file'],
        ['without-dependencies', 'don\'t remove dependencies'],
        ['verbose|v+',           'verbose output (can be provided multiple times)'],
    );
}

sub validate_args {
    my ($self, $opt, $args) = @_;

    Log::Any::Adapter->set('Dispatch', 'dispatcher' => use_module('Pakket::Log')->build_logger($opt->{'verbose'}));

    $opt->{'config'}   = $self->_determine_config($opt);
    $opt->{'packages'} = $self->_determine_packages($opt, $args);

    return;
}

sub execute {
    my ($self, $opt) = @_;

    my $uninstaller = use_module('Pakket::Controller::Uninstall')->new(
        'pakket_dir'           => $opt->{'config'}{'install_dir'},
        'packages'             => $opt->{'packages'},
        'without_dependencies' => $opt->{'without_dependencies'},
        'use_hardlinks'        => $opt->{'config'}{'use_hardlinks'} // 0,
        'keep_rollbacks'       => $opt->{'config'}{'keep_rollbacks'} // 1,
    );

    my @packages_for_uninstall = $uninstaller->get_list_of_packages_for_uninstall();

    print "We are going to remove:\n";
    for my $package (@packages_for_uninstall) {
        print "* $package->{category}/$package->{name}\n";
    }

    my $answer = prompt('Continue?', 'y');

    lc $answer eq 'y'
        and $uninstaller->uninstall();

    return;
}

1;

__END__

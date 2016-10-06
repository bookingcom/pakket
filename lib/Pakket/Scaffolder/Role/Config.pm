package Pakket::Scaffolder::Role::Config;
# ABSTRACT: scaffolder: role for config

use Moose::Role;

use File::HomeDir;
use Path::Tiny qw< path >;

use Pakket::ConfigReader;

has pakket_config => (
    is      => 'ro',
    isa     => 'HashRef',
    lazy    => 1,
    builder => '_build_pakket_config',
);

sub _build_pakket_config {
    my $config_file = path( File::HomeDir->my_home, '.pakket' );
    return +{} unless -f $config_file;
    my $config_reader = Pakket::ConfigReader->new(
        'type' => 'TOML',
        'args' => [ filename => $config_file ],
    );
    return $config_reader->read_config;
}

no Moose::Role;
1;
__END__

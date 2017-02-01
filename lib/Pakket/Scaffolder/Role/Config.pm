package Pakket::Scaffolder::Role::Config;
# ABSTRACT: scaffolder: role for config

use Moose::Role;
use File::HomeDir;
use Config::Any;
use Path::Tiny qw< path >;

has 'pakket_config' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'lazy'    => 1,
    'builder' => '_build_pakket_config',
);

sub _build_pakket_config {
    my $config_file = path( File::HomeDir->my_home, '.pakket' );

    my $cfg = Config::Any->load_files({
        'files'   => [ map "$config_file.$_", qw<json yaml yml conf cfg> ],
        'use_ext' => 1,
    });

    return $cfg;
}

no Moose::Role;
1;

__END__

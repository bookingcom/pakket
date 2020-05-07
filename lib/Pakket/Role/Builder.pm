package Pakket::Role::Builder;

# ABSTRACT: A role for all builders

use v5.22;
use Moose::Role;
use namespace::autoclean;

# core
use experimental qw(declared_refs refaliasing signatures);

# non core
use Path::Tiny;
use Types::Path::Tiny qw(Path);

requires qw(
    bootstrap
    bootstrap_prepare_modules
);

with qw(
    Pakket::Role::HasConfig
    Pakket::Role::HasLog
    Pakket::Role::RunCommand
);

has 'exclude_packages' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'default' => sub {+{}},
);

has 'bootstrap_dir' => (
    'is'      => 'ro',
    'isa'     => 'Path::Tiny',
    'lazy'    => 1,
    'builder' => '_build_bootstrap_dir',
);

has 'bootstrap_processing' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'lazy'    => 1,
    'default' => sub {+{}},
);

use constant {
    'BOOTSTRAP_DIR_TEMPLATE' => 'pakket-build-bootstrap-XXXXXX',
};

sub print_env ($self) {
    $self->log->debug($_, '=', $ENV{$_}) foreach sort keys %ENV;
    return;
}

sub _build_bootstrap_dir ($self) {
    return Path::Tiny->tempdir(BOOTSTRAP_DIR_TEMPLATE());
}

1;

__END__

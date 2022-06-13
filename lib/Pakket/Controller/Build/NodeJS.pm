package Pakket::Controller::Build::NodeJS;

# ABSTRACT: Build NodeJS Pakket packages

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

# core
use experimental qw(declared_refs refaliasing signatures);

with qw(
    Pakket::Role::Builder
    Pakket::Role::HasLog
);

sub execute ($self, %params) {
    $self->croak('Not properly implemented');

    # my ($self, $package, $build_dir, $top_pkg_dir, $prefix) = @_;

    # $self->log->info('Building NodeJS module:', $params{'name'});

    # if ($ENV{'NODE_NPM_REGISTRY'}) {
    #     $self->run_command($build_dir, [qw(npm set registry), $ENV{'NODE_NPM_REGISTRY'}], $opts);
    #     $params{'sources'} = $package;
    # }

    # my $success = $self->run_command($build_dir, [qw(npm install -g), $source], $opts);

    # if (!$success) {
    #     croak($log->critical("Failed to build $package"));
    # }

    # $log->info("Done preparing $package");

    return;
}

sub bootstrap_prepare_modules ($self) {
    return +([], {});
}

sub bootstrap ($self, $scaffolder, $modules, $requirements) {
    return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

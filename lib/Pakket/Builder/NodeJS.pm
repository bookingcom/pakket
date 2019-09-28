package Pakket::Builder::NodeJS;
# ABSTRACT: Build Perl Pakket packages

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use Carp       qw< croak >;
use English    qw< -no_match_vars >;
use Log::Any   qw< $log >;
use Path::Tiny qw< path >;
use Pakket::Log;
use Pakket::Utils qw< generate_env_vars >;

with qw<Pakket::Role::Builder>;

sub build_package {
    my ( $self, $package, $build_dir, $top_pkg_dir, $prefix, $use_prefix ) = @_;

    $log->info("Building NodeJS module: $package");

    my $opts = {
        'env' => {
            generate_env_vars($build_dir, $top_pkg_dir, $prefix, $use_prefix),
        },
    };

    my $source = $build_dir;

    if ( $ENV{'NODE_NPM_REGISTRY'} ) {
        $self->run_command( $build_dir,
            [ qw< npm set registry >, $ENV{'NODE_NPM_REGISTRY'} ], $opts );
        $source = $package;
    }

    my $success
        = $self->run_command( $build_dir, [ qw< npm install -g >, $source ],
        $opts );

    if ( !$success ) {
        croak( $log->critical("Failed to build $package") );
    }

    $log->info("Done preparing $package");

    return;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

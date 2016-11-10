package Pakket::Builder::NodeJS;
# ABSTRACT: Build Perl Pakket packages

use Moose;
use MooseX::StrictConstructor;
use English    qw< -no_match_vars >;
use Log::Any   qw< $log >;
use Path::Tiny qw< path >;
use Pakket::Log;
use Pakket::Utils qw< generate_env_vars >;

with qw<Pakket::Role::Builder>;

sub build_package {
    my ( $self, $package, $build_dir, $prefix ) = @_;

    $log->info("Building NodeJS module: $package");

    my $opts = {
        'env' => {
            generate_env_vars($prefix),
        },
    };

    my $original_dir = Path::Tiny->cwd;
    my $install_base = $prefix->absolute;

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
        $log->critical("Failed to build $package");
        exit 1;
    }

    $log->info("Done preparing $package");

    return;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

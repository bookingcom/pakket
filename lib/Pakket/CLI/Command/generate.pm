package Pakket::CLI::Command::generate;
# ABSTRACT: The pakket install command

use strict;
use warnings;
use Log::Any::Adapter;
use Path::Tiny qw< path  >;
use List::Util qw< first >;

use Pakket::CLI '-command';
use Pakket::Log;
use Pakket::Scaffolder::Perl;

sub abstract    { 'Scaffold a project' }
sub description { 'Scaffold a project' }

sub opt_spec {
    return (
        [
            'name=s',
            'category/module name (e.g. "perl/Moose")',
        ],
        [
            'cpanfile=s',
            'cpanfile to configure from',
        ],
        [
            'config-dir=s',
            'directory to write the configuration to (TOML files)',
            { required => 1 },
        ],
        [
            'source-dir=s',
            'directory to write the sources to (downloads if provided)',
        ],
        [
            'index-file=s',
            'file to generate json configuration to',
        ],
        [
            'additional_phase=s@',
            "additional phases to use ('develop' = author_requires, 'test' = test_requires). configure & runtime are done by default.",
        ],
        [
            'extract',
            'extract downloaded source tarball',
            { default => 0 },
        ],
        [ 'verbose|v+',     'verbose output (can be provided multiple times)' ],
    );
}

sub validate_args {
    my ( $self, $opt, $args ) = @_;

    Log::Any::Adapter->set( 'Dispatch',
        'dispatcher' => Pakket::Log->build_logger( $opt->{'verbose'} ) );

    @{ $args } and $self->usage_error("No extra arguments are allowed.\n");

    my $category;
    my $name;
    my $type;

    if ( $opt->{'name'} ) {
        ( $category, $name ) = split /\//xms => $opt->{'name'};
        first { $_ eq $category } qw< perl > # add supported categories
            or $self->usage_error( "Wrong 'name' format\n" );
        $type = 'module';
    }
    elsif ( $opt->{'cpanfile'} ) {
        $category = 'perl';
        $name     = $opt->{'cpanfile'};
        $type     = 'cpanfile';
    }
    else {
        $self->usage_error( "Must provide 'name' or 'cpanfile'\n" ); # future: others
    }

    $self->{'config'} = +{
        name       => $name,
        category   => $category,
        type       => $type,
        config_dir => $opt->{'config_dir'},
        source_dir => $opt->{'source_dir'},
        index_file => $opt->{'index_file'},
        extract    => $opt->{'extract'},
    };
}

sub execute {
    my $self = shift;
    my $scaffolder = $self->_get_scaffolder();
    $scaffolder->run;
}

sub _get_scaffolder {
    my $self = shift;
    $self->{'config'}{'category'} eq 'perl'
        and return $self->gen_scaffolder_perl();
    die "failed to create a scaffolder\n";
}

sub gen_scaffolder_perl {
    my $self   = shift;
    my $config = $self->{'config'};

    return Pakket::Scaffolder::Perl->new(
        config_dir        => $config->{'config_dir'},
        json_file         => $config->{'index_file'},
        source_dir        => $config->{'source_dir'},
        extract           => $config->{'extract'},
        $config->{'type'} => $config->{'name'},
    );
}

1;
__END__

package Pakket::Config;
# ABSTRACT: Read and represent Pakket configurations

use Moose;
use MooseX::StrictConstructor;
use Config::Any;
use Path::Tiny        qw< path >;
use Types::Path::Tiny qw< Path >;

has 'paths' => (
    'is'      => 'ro',
    'isa'     => 'ArrayRef',
    'default' => sub { return ['/etc/pakket', '~/.pakket'] },
);

has 'extensions' => (
    'is'      => 'ro',
    'isa'     => 'ArrayRef',
    'default' => sub { return [qw< json yaml yml conf cfg >] },
);

has 'files' => (
    'is'      => 'ro',
    'isa'     => 'ArrayRef',
    'lazy'    => 1,
    'default' => sub {
        my $self = shift;

        if ( $ENV{PAKKET_CONFIG_FILE} ) {
            return [ $ENV{PAKKET_CONFIG_FILE} ];
        }

        my %files;
        foreach my $path (@{$self->{paths}}) {
            foreach my $extension (@{$self->{extensions}}) {
                my $file = path("$path.$extension");

                $file->exists
                    or next;

                $files{$path}
                    and die "Multiple extensions for same config file name";

                $files{$path} = $file;
            }

            $files{$path}
                and return [ $files{$path} ];
        }

        die "Could not find any config file";
    },
);

sub read_config {
    my $self   = shift;
    my $config = Config::Any->load_files({
        'files'   => $self->files,
        'use_ext' => 1,
    });

    my %cfg;
    foreach my $config_chunk ( @{$config} ) {
        foreach my $filename ( keys %{$config_chunk} ) {
            my %config_part = %{ $config_chunk->{$filename} };
            @cfg{ keys(%config_part) } = values %config_part;
        }
    }

    return \%cfg;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

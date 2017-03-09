package Pakket::Config;
# ABSTRACT: Read and represent Pakket configurations

use Moose;
use MooseX::StrictConstructor;
use Config::Any;
use Path::Tiny        qw< path >;
use Types::Path::Tiny qw< Path >;
use Log::Any          qw< $log >;
use Carp              qw< croak >;

has 'paths' => (
    'is'      => 'ro',
    'isa'     => 'ArrayRef',
    'default' => sub { return ['~/.pakket', '/etc/pakket'] },
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
                    and croak $log->criticalf(
                        "Multiple extensions for same config file name: %s and %s",
                        $files{$path}, $file);

                $files{$path} = $file;
            }

            $files{$path}
                and return [ $files{$path} ];
        }

        return [];
    },
);

sub read_config {
    my $self   = shift;

    @{ $self->files }
        or return {};

    my $config = Config::Any->load_files({
        'files'   => $self->files,
        'use_ext' => 1,
    });

    my %cfg;
    foreach my $config_chunk ( @{$config} ) {
        foreach my $filename ( keys %{$config_chunk} ) {
            my %config_part = %{ $config_chunk->{$filename} };
            @cfg{ keys(%config_part) } = values %config_part;
            $log->info("Using config file $filename");
        }
    }

    return \%cfg;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

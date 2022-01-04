package Pakket::Config;

# ABSTRACT: Read and represent Pakket configurations

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

# core
use Carp;
use experimental qw(declared_refs refaliasing signatures);

# non core
use Config::Any;
use Log::Any qw($log);
use Path::Tiny;
use Types::Path::Tiny qw(Path);

has 'paths' => (
    'is'      => 'ro',
    'isa'     => 'ArrayRef',
    'default' => sub {['~/.config/pakket', '/etc/pakket']},
);

has 'extensions' => (
    'is'      => 'ro',
    'isa'     => 'ArrayRef',
    'default' => sub {[qw(json yaml yml conf cfg)]},
);

has 'files' => (
    'is'      => 'ro',
    'isa'     => 'ArrayRef',
    'lazy'    => 1,
    'builder' => '_build_files',
);

has 'env_name' => (
    'is'      => 'ro',
    'isa'     => 'Str',
    'default' => 'PAKKET_CONFIG_FILE',
);

has 'required' => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'default' => 0,
);

sub read_config ($self) {
    $self->files->@*
        or return {};

    my $config = Config::Any->load_files({
            'files'   => $self->files,
            'use_ext' => 1,
        },
    );

    my %cfg;
    foreach my $config_chunk ($config->@*) {
        foreach my $filename (keys $config_chunk->%*) {
            my \%config_part = $config_chunk->{$filename};
            @cfg{keys (%config_part)} = values %config_part;
            $log->debug('Using config file:', $filename);
        }
    }

    return \%cfg;
}

sub _build_files ($self) {
    if ($ENV{$self->env_name}) {
        return [$ENV{$self->env_name}];
    }

    my %files;
    foreach my $path ($self->{'paths'}->@*) {
        foreach my $extension ($self->{'extensions'}->@*) {
            my $file = path("$path.$extension");

            $file->exists
                or next;

            $files{$path}
                and croak $log->criticalf('Multiple extensions for same config file name: %s and %s',
                $files{$path}, "$file");

            $files{$path} = $file;
        }

        # We found a file in order of precedence so we return it
        $files{$path}
            and return [$files{$path}];
    }

    # Could not find any files
    if ($self->required) {
        my \@paths = $self->{'paths'};
        croak($log->fatal("Please specify an existing config file: $self->{'env_name'}, @{[@paths]} {json, yaml}"));
    }

    return [];
}

__PACKAGE__->meta->make_immutable;

1;

__END__

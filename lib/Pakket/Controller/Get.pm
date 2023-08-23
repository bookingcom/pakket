package Pakket::Controller::Get;

# ABSTRACT: Get packages, parcels and specs

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

# core
use Fatal        qw(binmode);
use experimental qw(declared_refs refaliasing signatures switch);

# non core
use JSON::MaybeXS   qw(decode_json);
use Module::Runtime qw(use_module);
use YAML::XS;

extends qw(Pakket::Controller::BaseRemoteOperation);

has 'file' => (
    'is'  => 'ro',
    'isa' => 'Maybe[Str]',
);

has 'output' => (
    'is'      => 'ro',
    'isa'     => 'Str',
    'default' => 'yaml',
);

sub execute ($self) {
    my $repo = $self->get_repo();

    my ($query) = $self->queries->@*;

    if ($query->category eq 'perl' && $query->is_module()) {
        my $cpan = use_module('Pakket::Helper::Cpan')->new;
        $query->{'name'} = $cpan->determine_distribution($query->name);
        $query->clear_short_name;
    }

    my \@packages = $self->check_against_repository($repo, {$query->short_name => $query});

    my $package = $packages[0];
    my $file    = $repo->retrieve_location($package->id);

    if (!$self->file) {
        if ($repo->type eq 'spec') {
            $self->{'file'} = '-';
        } else {
            my $name = join ('-', $package->category, $package->name, $package->version, $package->release);
            $self->{'file'} = join ('.', $name, $repo->backend->file_extension);
        }
    }

    if ($self->output eq 'json' && $repo->backend->file_extension =~ m/json$/) {
        ## do nothing
    } elsif ($self->output eq 'yaml' && $repo->backend->file_extension =~ m/json$/) {
        YAML::XS::DumpFile($file, decode_json($file->slurp_raw));
    }

    if ($self->file eq '-') {
        binmode STDOUT
            and print {*STDOUT} $file->slurp_utf8();
    } else {
        $self->log->noticef(q{Retreiving object '%s' to: %s}, $package->id, $self->file);
        $file->copy($self->file);
    }

    return 0;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

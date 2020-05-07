package Pakket::Controller::Get;

# ABSTRACT: Get packages, parcels and specs

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

# core
use Fatal qw(binmode);
use experimental qw(declared_refs refaliasing signatures switch);

# non core
use Module::Runtime qw(use_module);

extends qw(Pakket::Controller::BaseRemoteOperation);

has 'file' => (
    'is'  => 'ro',
    'isa' => 'Maybe[Str]',
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
        given ($repo->type) {
            when ('spec') {
                $self->{'file'} = '-';
            }
            default {
                my $name = join ('-', $package->category, $package->name, $package->version, $package->release);
                $self->{'file'} = join ('.', $name, $repo->backend->file_extension);
            }
        }
    }

    if ($self->file eq '-') {
        binmode STDOUT
            and print {*STDOUT} $file->slurp_raw();
    } else {
        $self->log->noticef(q{Retreiving object '%s' to: %s}, $package->id, $self->file);
        $file->copy($self->file);
    }

    return 0;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

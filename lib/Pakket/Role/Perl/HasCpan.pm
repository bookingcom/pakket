package Pakket::Role::Perl::HasCpan;

# ABSTRACT: Provide CPAN access support

use v5.22;
use Moose::Role;
use namespace::autoclean;

# core
use experimental qw(declared_refs refaliasing signatures);

# local
use Pakket::Helper::Cpan;

has 'cpan_02packages_file' => (
    'is'  => 'ro',
    'isa' => 'Maybe[Str]',
);

has 'cpan' => (
    'is'      => 'ro',
    'isa'     => 'Pakket::Helper::Cpan',
    'lazy'    => 1,
    'default' => sub ($self) {
        Pakket::Helper::Cpan->new(
            'config' => $self->config,
            ('cpan_02packages_file' => $self->cpan_02packages_file) x !!$self->cpan_02packages_file,
            $self->%{qw(log log_depth)},
        );
    },
    'handles' => ['determine_distribution', 'get_release_info', 'meta_load'],
);

1;

__END__

package Pakket::Scaffolder::Role::Backend;
# ABSTRACT: scaffolder: role for backend

use Moose::Role;

use HTTP::Tiny;

requires 'run';

has [qw< config_dir source_dir json_file >]=> (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has extract => (
    is      => 'ro',
    isa     => 'Bool',
    default => 0,
);

has ua => (
    is      => 'ro',
    lazy    => 1,
    builder => '_build_ua',
);

sub _build_ua {
    return HTTP::Tiny->new();
}

no Moose::Role;
1;
__END__

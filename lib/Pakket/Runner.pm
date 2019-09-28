package Pakket::Runner;
# ABSTRACT: Run Pakket-based applications

use v5.22;
use Moose;
use Types::Path::Tiny qw< AbsPath >;

has 'active_path' => (
    'is'       => 'ro',
    'isa'      => AbsPath,
    'coerce'   => 1,
    'required' => 1,
);

sub run {
    my ( $self, @args ) = @_;

    my $active_path = $self->active_path;

    # Avoid uninitialized values
    my $ENV_PATH            = $ENV{'PATH'}            // '';
    my $ENV_LD_LIBRARY_PATH = $ENV{'LD_LIBRARY_PATH'} // '';

    local $ENV{'PATH'}            = "$active_path/bin:$ENV_PATH";
    local $ENV{'PERL5LIB'}        = "$active_path/lib/perl5";
    local $ENV{'LD_LIBRARY_PATH'} = "$active_path/lib:$ENV_LD_LIBRARY_PATH";

    # FIXME: Move to IPC::Open3, use the logger, etc.
    # XXX:   Should this just use the RunCommand role?
    if (@args) {
        system @args;
    } else {
        print "$_=$ENV{$_}\n" for qw< PATH PERL5LIB LD_LIBRARY_PATH >;
    }

    return 0;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

package Pakket::Scaffolder::Role::Terminal;
# ABSTRACT: scaffolder: role for output handling

use Moose::Role;

has depth => (
    is      => 'ro',
    isa     => 'Num',
    default => 0,
    writer  => 'set_depth',
);

sub spaces {
    my $self = shift;
    return ' 'x( $self->depth * 2 );
}


no Moose::Role;
1;
__END__

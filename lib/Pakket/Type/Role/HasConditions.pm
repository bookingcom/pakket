package Pakket::Type::Role::HasConditions;

# ABSTRACT: Role provides conditions for filtering packages

use v5.22;
use Moose::Role;
use namespace::autoclean;

# core
use experimental qw(declared_refs refaliasing signatures);

use constant {
    'COND_REGEX' => qr{
        \A
        \s* (?<op> >=|<=|==|!=|[<>])? \s* (?<version> \S*) \s*
        \z
    }xms,
    'DEFAULT_CONDITION' => ['>=', '0'],
};

has 'requirement' => (
    'is'      => 'ro',
    'isa'     => 'Str',
    'default' => '0',
);

has 'conditions' => (
    'is'      => 'ro',
    'isa'     => 'ArrayRef',
    'lazy'    => 1,
    'builder' => '_build_conditions',
);

sub determine_condition ($req_str, $strict = 0) {
    my @condition = $req_str =~ COND_REGEX();
    $condition[0] //= ($strict && $condition[1] ? '==' : '>=');
    return \@condition;
}

sub _build_conditions ($self) {
    my @conditions;
    if ($self->requirement) {
        foreach my $req_str (split m/,/xms, $self->requirement) {
            $req_str
                or next;
            push (@conditions, determine_condition($req_str, !$self->as_prereq));
        }
    }
    @conditions
        or push (@conditions, DEFAULT_CONDITION());

    return \@conditions;
}

1;

__END__

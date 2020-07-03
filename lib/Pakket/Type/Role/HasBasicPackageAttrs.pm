package Pakket::Type::Role::HasBasicPackageAttrs;

# ABSTRACT: Role provides basic package attributes

use v5.22;
use Moose::Role;
use namespace::autoclean;

# core
use Carp;
use experimental qw(declared_refs refaliasing signatures);

# non core
use Log::Any qw($log);

# local
use Pakket::Utils::Package qw(
    canonical_name
    parse_requirement
);

use constant {
    'VALID_CATEGORIES' => {
        'native' => 1,
        'perl'   => 1,
    },
};

requires qw(
    category
    name
    as_prereq
);

sub BUILD ($self, @) {
    exists VALID_CATEGORIES()->{$self->category}
        or croak($log->critical('Unsupported category:', $self->category));

    return;
}

sub requirement ($self) {
    return parse_requirement($self->version, $self->as_prereq ? '>=' : '==');
}

sub req_str ($self) {
    return join (' ', $self->requirement);
}

sub is_module ($self) {
    return $self->name =~ m/::/;
}

1;

__END__

package Pakket::Type::BasePackage;

# ABSTRACT: An object representing a base package

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

# core
use Carp;
use English '-no_match_vars';
use experimental qw(declared_refs refaliasing signatures);

# non core
use Log::Any qw($log);

# local
use Pakket::Utils::Package qw(
    PAKKET_PACKAGE_STR
);

has [qw(category name)] => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
);

has [qw(as_prereq)] => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'lazy'    => 1,
    'default' => 0,
);

has 'short_name' => (
    'is'      => 'ro',
    'isa'     => 'Str',
    'lazy'    => 1,
    'default' => sub ($self) {join ('/', $self->category, $self->name)},
    'clearer' => 'clear_short_name',
);

sub BUILDARGS ($class, %args) {
    $args{'name'}
        or croak($log->criticalf('Name is a demanded field'));

    my $default_category = delete $args{'default_category'};
    if (!$args{'category'}) {
        if ($args{'name'} =~ PAKKET_PACKAGE_STR()) {
            $args{'category'} = $LAST_PAREN_MATCH{'category'} // $default_category;
            $args{'name'}     = $LAST_PAREN_MATCH{'name'};
            $args{'requirement'} ||= $LAST_PAREN_MATCH{'version'} if $LAST_PAREN_MATCH{'version'};
            $args{'release'}     ||= $LAST_PAREN_MATCH{'release'} if $LAST_PAREN_MATCH{'release'};
        }
    }

    $args{'category'}
        or croak($log->criticalf(q{Invalid category '%s' for package: '%s'}, $args{'category'}, $args{'name'}));

    Pakket::Utils::Package::validate_name($args{'name'});

    return \%args;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

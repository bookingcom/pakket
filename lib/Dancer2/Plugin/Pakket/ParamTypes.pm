package Dancer2::Plugin::Pakket::ParamTypes;

# ABSTRACT: Parameter types for the Dancer2 Pakket app

use v5.22;
use strict;
use warnings;
use namespace::autoclean;

use Dancer2::Plugin;

use constant {'HTTP_USER_ERROR' => 400};

extends qw(Dancer2::Plugin::ParamTypes);

plugin_keywords('with_types');

sub BUILD {
    my $self = shift;

    $self->register_type_check(
        'Str' => sub {defined $_[0] && length $_[0]},
    );

    $self->register_type_action(
        'MissingID' => sub {
            send_error('Missing or incorrect ID', HTTP_USER_ERROR());
        },
    );

    $self->register_type_action(
        'MissingName' => sub {
            send_error('Missing or incorrect Name', HTTP_USER_ERROR());
        },
    );

    $self->register_type_action(
        'MissingCategory' => sub {
            send_error('Missing or incorrect Category', HTTP_USER_ERROR());
        },
    );

    $self->register_type_action(
        'MissingContent' => sub {
            send_error('Missing or incorrect content', HTTP_USER_ERROR());
        },
    );

    $self->register_type_action(
        'MissingFilename' => sub {
            send_error('Missing or incorrect filename', HTTP_USER_ERROR());
        },
    );

    return;
}

sub with_types {
    my $self = shift;
    return $self->SUPER::with_types(@_);
}

1;

__END__

package Pakket::Role::HasLog;

# ABSTRACT: Provides logger for class

use v5.22;
use Moose::Role;
use namespace::autoclean;

# core
use Carp ();
use vars qw(@CARP_NOT);
use experimental qw(declared_refs refaliasing signatures);

# non core
#use Log::Any '$log', 'prefix' => ''; ## no critic [ValuesAndExpressions::RequireInterpolationOfMetachars]
use Log::Any ();

use constant {
    'LOG_PREFIX' => '|   ',
};

has 'log_depth' => (
    'is'      => 'rw',
    'isa'     => 'HashRef',
    'default' => sub {+{'value' => 0}},

    #'trigger' => sub ($self, @) {
    #$self->log->{'prefix'} = LOG_PREFIX() x $self->log_depth->{'value'};
    #},
);

has 'log' => (
    'is'       => 'ro',
    'required' => 1,
);

sub BUILDARGS ($class, %args) {
    $args{'log'} //= Log::Any->get_logger('prefix' => '');

    return \%args;
}

sub log_depth_change ($self, $value) {
    $self->log_depth->{'value'} = $self->log_depth->{'value'} + $value;
    $self->log->{'prefix'}      = LOG_PREFIX() x $self->log_depth->{'value'};
    return $self->log_depth->{'value'};
}

sub log_depth_set ($self, $value) {
    $self->log_depth->{'value'} = $value;
    $self->log->{'prefix'}      = LOG_PREFIX() x $self->log_depth->{'value'};
    return $self->log_depth->{'value'};
}

sub log_depth_get ($self) {
    return $self->log_depth->{'value'};
}

sub croak ($self, @messages) {
    my $msg = join (' ', @messages);
    $self->log->critical($msg);
    Carp::croak($msg);
}

sub croakf ($self, $format, @messages) {
    my $msg = sprintf ($format, @messages);
    $self->log->critical($msg);
    Carp::croak($msg);
}

1;

__END__

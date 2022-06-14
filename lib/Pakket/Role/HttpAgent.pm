package Pakket::Role::HttpAgent;

# ABSTRACT: Role for Http requests

use v5.22;
use Moose::Role;
use namespace::autoclean;

# core
use Carp;
use experimental qw(declared_refs refaliasing signatures);

# non core
use Log::Any qw($log);
use Mojo::UserAgent;

has 'extract' => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'default' => 0,
);

has 'ua' => (
    'is'      => 'ro',
    'isa'     => 'Mojo::UserAgent',
    'lazy'    => 1,
    'builder' => '_build_ua',
);

sub http_get ($self, $url, @params) {
    my $tx = $self->ua->get($url, @params);

    if ($tx->res->is_error) {
        croak $log->criticalf('Could not GET request "%s": %s %s', $url, $tx->res->code, $tx->res->message);
    }

    return $tx;
}

sub http_get_nt ($self, $url, @params) {
    my $tx = $self->ua->get($url, @params);

    if ($tx->res->is_error) {
        croak $log->criticalf('Could not GET request "%s": %s %s', $url, $tx->res->code, $tx->res->message);
    }

    return $tx;
}

sub http_post ($self, $url, @params) {
    my $tx = $self->ua->post($url, @params);

    if ($tx->res->is_error) {
        croak $log->criticalf('Could not POST request "%s": %s %s', $url, $tx->res->code, $tx->res->message);
    }

    return $tx;
}

sub http_put ($self, $url, @params) {
    my $tx = $self->ua->put($url, @params);

    if ($tx->res->is_error) {
        croak $log->criticalf('Could not PUT request "%s": %s %s', $url, $tx->res->code, $tx->res->message);
    }

    return $tx;
}

sub http_delete ($self, $url, @params) {
    my $tx = $self->ua->delete($url, @params);

    if ($tx->res->is_error) {
        croak $log->criticalf('Could not DELETE request "%s": %s %s', $url, $tx->res->code, $tx->res->message);
    }

    return $tx;
}

sub _build_ua {
    return Mojo::UserAgent->new->max_redirects(4)->tap(sub {$_->proxy->detect});
}

1;

__END__

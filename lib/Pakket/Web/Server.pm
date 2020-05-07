package Pakket::Web::Server;

# ABSTRACT: Start a Pakket server

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

use Log::Any qw($log);
use Plack::Runner;

use Pakket::Web::App;

has 'port' => (
    'is'        => 'ro',
    'isa'       => 'Int',
    'predicate' => 'has_port',
);

sub run {
    my $self = shift;

    Pakket::Web::App->setup();
    my $app    = Pakket::Web::App->to_app;
    my $runner = Plack::Runner->new();

    my @runner_opts = ($self->has_port ? ('--port', $self->port) : ());

    $runner->parse_options(@runner_opts);
    return $runner->run($app);
}

__PACKAGE__->meta->make_immutable;

1;

__END__

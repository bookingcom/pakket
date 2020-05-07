package Pakket::PSGI;

# ABSTRACT: Pakket psgi entrypoint

use v5.22;
use strict;
use warnings;

use Pakket::Web::App;

Pakket::Web::App->setup;
Pakket::Web::App->to_app;

1;

__END__

#!/usr/bin/env perl

# ABSTRACT: The Pakket meta packaging application
# PODNAME: pakket

use v5.22;
use warnings;
use strict;

use Pakket;

my $app = Pakket->new();

exit ($app->run() // 0);

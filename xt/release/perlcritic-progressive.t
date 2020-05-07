#!/usr/bin/env perl
# THIS SHOULD BE RELEASE_TESTING AND AUHTOR_TESTING

use v5.22;
use strict;
use warnings;

# core
use lib '.';

# non core
use Test::More;

# local
use t::lib::Utils;

eval {
    require Test::Perl::Critic::Progressive;
    Test::Perl::Critic::Progressive::set_critic_args('-profile' => 't/.perlcriticrc');
    1;
} or do {
    plan('skip_all' => 'T::P::C::Progressive required for this test');
};

Test::Perl::Critic::Progressive::progressive_critic_ok();

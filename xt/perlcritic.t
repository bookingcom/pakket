#!/usr/bin/env perl
# THIS SHOULD BE RELEASE_TESTING AND AUHTOR_TESTING

use v5.22;
use strict;
use warnings;

use Test::More;

eval {
    require Test::Perl::Critic::Progressive;
    1;
} or do {
    plan('skip_all' => 'T::P::C::Progressive required for this test');
};

Test::Perl::Critic::Progressive::progressive_critic_ok();

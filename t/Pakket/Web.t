#!/usr/bin/env perl

use v5.28;
use warnings;

use lib '.';

use Test::Mojo;
use Test2::V0;
use Test2::Tools::Spec;

use t::lib::Utils qw(test_web_prepare_context);

use experimental qw(declared_refs refaliasing signatures);

## no critic [ValuesAndExpressions::ProhibitLongChainsOfMethodCalls]

describe 'Pakket::Web legacy' => sub {
    Test2::Tools::Spec::spec_defaults tests => (async => 1);

    my (%ctx, $t);

    before_all 'prepare test environment' => sub {
        \%ctx = test_web_prepare_context();
        $t = Test::Mojo->new(
            'Pakket::Web',
            {                                                                  # prevent using default config files
                'log_file'     => '/test.log',
                'config_files' => ['/test.json'],
            },
        );
    };

    tests 'test /' => sub {
        $t->get_ok('/')->status_is(200)->content_like(qr{<title>Pakket status page</title>}i);
    };

    tests 'test /info' => sub {
        $t->get_ok('/info')->status_is(200)->json_has('/repositories')->json_has('/repositories/0')
            ->json_has('/repositories/0/path')->json_has('/repositories/0/type')->json_like('/version' => qr{^3});
    };

    tests 'test /all_packages' => sub {
        $t->get_ok('/all_packages')->status_is(200);
    };

    tests 'test /updates' => sub {
        $t->get_ok('/updates')->status_is(200)->json_has('/items');
    };

    tests 'test /snapshot' => sub {
        my @packages = ('native/zlib=1.2.11:1', 'perl/version=0.9924:1');
        my $post     = $t->post_ok('/co7/5.28.1/parcel/snapshot' => json => \@packages);
        $post->status_is(200);

        my $result      = $post->tx->result->json;
        my $snapshot_id = $result->{'id'};

        $t->get_ok('/snapshot')->status_is(200);
        $t->get_ok('/snapshots')->status_is(200);

        $t->get_ok('/snapshots/42')->status_is(404);

        $t->get_ok("/snapshot/$snapshot_id")->status_is(200)->json_is('/id' => $snapshot_id)
            ->json_is('/items' => \@packages)->json_has('/path')->json_has('/type');
        $t->get_ok("/snapshot?id=$snapshot_id")->status_is(200)->json_is('/id' => $snapshot_id)
            ->json_is('/items' => \@packages)->json_has('/path')->json_has('/type');
    };
};

done_testing();

__END__

use strict;
use warnings;
use Test::More 'tests' => 2;
use Test::Fatal;
use Pakket::Repository;

can_ok( Pakket::Repository::, qw< backend latest_version packages_list > );

like(
    exception { Pakket::Repository->new() },
    qr{Attribute \s \(backend\) \s is \s required \s at \s constructor}xms,
    'Backend is required to create a Pakket::Repository object',
);

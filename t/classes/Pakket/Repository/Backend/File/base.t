use strict;
use warnings;
use Test::More 'tests' => 5;
use Test::Fatal;
use Path::Tiny qw< path >;
use Pakket::Repository::Backend::File;

can_ok(
    Pakket::Repository::Backend::File::,
    qw< filename repo_index packages_list >,
);

my $index_file = path( qw< t corpus indexes eg.json > );

like(
    exception { Pakket::Repository::Backend::File->new() },
    qr{^ Attribute \s \(filename\) \s is \s required \s at \s constructor}xms,
    'filename is required to create a new File backend class',
);

is(
    exception {
        Pakket::Repository::Backend::File->new(
            'filename' => $index_file->stringify,
        );
    },
    undef,
    'filename attribute can be a string',
);

is(
    exception {
        Pakket::Repository::Backend::File->new( 'filename' => $index_file, );
    },
    undef,
    'filename attribute can be a Path::Tiny object',
);

my $backend = Pakket::Repository::Backend::File->new(
    'filename' => $index_file,
);

subtest 'Required methods' => sub {
    my $list = [ sort @{ $backend->packages_list } ];

    is_deeply(
        $list,
        [ qw<
            fake_category_1/fake_package_name_1_1=1.1.0
            fake_category_1/fake_package_name_1_1=1.1.1
            fake_category_2/fake_package_name_2_1=2.1.0
            fake_category_2/fake_package_name_2_1=2.1.1
            fake_category_2/fake_package_name_2_2=2.2.0
            fake_category_2/fake_package_name_2_2=2.2.1
        >, ],
        'packages_list returns flat list of packages',
    );

    is(
        $backend->latest_version( 'fake_category_2', 'fake_package_name_2_1' ),
        '2.1.1',
        'latest_version returns the latest version of a package',
    );
};

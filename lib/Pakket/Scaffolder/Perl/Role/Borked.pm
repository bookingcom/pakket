package Pakket::Scaffolder::Perl::Role::Borked;
# ABSTRACT: scaffolder: perl: known issues

use Moose::Role;

has 'known_incorrect_name_fixes' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'default' => sub {
        +{
            'App::Fatpacker'            => 'App::FatPacker',
            'Test::YAML::Meta::Version' => 'Test::YAML::Meta', # not sure about this
            'Net::Server::SS::Prefork'  => 'Net::Server::SS::PreFork',
        }
    },
);

has 'known_incorrect_version_fixes' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'default' => sub {
        +{
            'Data-Swap'         => '0.08',
            'Encode-HanConvert' => '0.35',
            'ExtUtils-Constant' => '0.23',
            'Frontier-RPC'      => '0.07',
            'Getopt-Long'       => '2.49',
            'IO-Capture'        => '0.05',
            'Memoize-Memcached' => '0.04',
            'Statistics-Regression' => '0.53',
            'Data-HexDump-Range' => 'v0.13.72',
        }
    },
);

has 'known_incorrect_dependencies' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'default' => sub {
        +{
            'Module-Install' => {
                'libwww-perl' => 1,
                'PAR-Dist'    => 1,
            },
            'libwww-perl'    => {
                'NTLM' => 1,
            },
        }
    },
);

has 'known_names_to_skip' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'default' => sub {
        +{
            'perl'                    => 1,
            'tinyperl'                => 1,
            'perl_mlb'                => 1,
            'HTTP::GHTTP'             => 1,
            'Text::MultiMarkdown::XS' => 1, # ADOPTME
            'URI::file'               => 1, # in URI, appears with weird version
            'URI::Escape'             => 1, # in URI, appears with weird version
        }
    },
);

no Moose::Role;
1;
__END__

package Pakket::Web::Snapshot;

# ABSTRACT: A web snapshot app

use v5.22;
use Dancer2 'appname' => 'Pakket::Web';
use Dancer2::Plugin::Pakket::ParamTypes;
use namespace::autoclean;

# core
use Carp;
use Digest::SHA qw(sha256_hex);
use experimental qw(declared_refs refaliasing signatures);

# non core
use Log::Any qw($log);
use Net::Amazon::S3;
use Net::Amazon::S3::Client;
use Net::Amazon::S3::Client::Object;
use Ref::Util qw(is_arrayref is_hashref);

# local
use Pakket::Type::PackageQuery;
use Pakket::Utils::DependencyBuilder;

## no critic [Modules::RequireExplicitInclusion]

sub expose ($class, $config, $spec_repo, @repos) {
    my $s3 = Net::Amazon::S3::Client->new(
        's3' => Net::Amazon::S3->new(
            'host'                  => $config->{'host'},
            'aws_access_key_id'     => $config->{'aws_access_key_id'},
            'aws_secret_access_key' => $config->{'aws_secret_access_key'},
            'retry'                 => 1,
        ),
    );
    my $bucket = $s3->bucket('name' => $config->{'bucket'});

    my $dependency_builder = Pakket::Utils::DependencyBuilder->new(
        'spec_repo' => $spec_repo,
    );

    get '/snapshot' => with_types [['query', 'id', 'Str', 'MissingID']] => sub {
        my $id     = query_parameters->get('id');
        my $object = $bucket->object(
            'key'          => $id,
            'content_type' => 'application/json',
        );

        $object->exists
            or send_error("Not found: $id", 404);

        return encode_json({
                'id'    => $id,
                'items' => $object->get_decoded,
            },
        );
    };

    foreach my $r (@repos) {
        $r->{'repo_config'}{'type'} eq 'parcel'
            or next;

        my $prefix = $r->{'repo_config'}{'path'};
        prefix $prefix => sub {
            post '/snapshot' => sub {
                my $data = decode_json(request->body);
                defined $data && is_arrayref($data)
                    or send_error('Bad input', 400);

                my @ids      = sort $data->@*;
                my $checksum = sha256_hex($prefix, @ids);

                my $result = [];
                my $object = $bucket->object(
                    'key'          => $checksum,
                    'content_type' => 'application/json',
                );
                if ($object->exists) {
                    $result = decode_json($object->get);
                } else {
                    eval {
                        my @queries = map {
                            Pakket::Type::PackageQuery->new_from_string($_,
                                'default_category' => $config->{'default_category'})
                        } @ids;
                        my $requirements = $dependency_builder->recursive_requirements(
                            \@queries,
                            'parcel_repo' => $r->{'repo'},
                            'phases'      => ['runtime'],
                            'types'       => ['requires'],
                        );
                        $result = [map $_->id, $dependency_builder->validate_requirements($requirements)->@*];
                        $object->put(encode_json($result));
                        1;
                    } or do {
                        chomp (my $error = $@ || 'zombie error');
                        send_error($error, 500);
                    };

                }

                return encode_json({
                        'id'    => $checksum,
                        'items' => $result,
                    },
                );
            };
        };
    }

    return;
}

1;

__END__

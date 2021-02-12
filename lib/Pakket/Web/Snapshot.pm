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
use Module::Runtime qw(require_module);
use Ref::Util qw(is_arrayref is_hashref);

# local
use Pakket::Repository;
use Pakket::Type::PackageQuery;
use Pakket::Utils::DependencyBuilder;

## no critic [Modules::RequireExplicitInclusion]

sub expose ($class, $config, $spec_repo, @repos) {
    my \%repo_config = $config->{'repository'};
    my $repo_type    = ucfirst lc delete $repo_config{'type'};
    my $repo_class   = "Pakket::Repository::Backend::$repo_type";
    eval {
        require_module($repo_class);
        1;
    } or do {
        croak($log->critical("Failed to load repo backend '$repo_class': $@"));
    };
    my $snapshots_repo = $repo_class->new(\%repo_config);

    my $dependency_builder = Pakket::Utils::DependencyBuilder->new(
        'spec_repo' => $spec_repo,
    );

    get '/snapshots' => sub {
        return encode_json($snapshots_repo->all_object_ids());
    };

    get '/snapshot' => with_types [['query', 'id', 'Str', 'MissingID']] => sub {
        my $id = query_parameters->get('id');
        my \@objects = $snapshots_repo->all_object_ids_by_name('', $id);

        @objects
            or send_error("Not found: $id", 404);

        return encode_json({
                'id'    => $id,
                'items' => decode_json($snapshots_repo->retrieve_content($id)),
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
                my \@objects = $snapshots_repo->all_object_ids_by_name('', $checksum);

                if (@objects == 1) {
                    $result = decode_json($snapshots_repo->retrieve_content($checksum));
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
                        $snapshots_repo->store_content($checksum, encode_json($result));
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

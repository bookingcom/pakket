package Pakket::Web::Controller::Snapshot;

# ABSTRACT: A web snapshot controller

use v5.28;
use namespace::autoclean;
use Mojo::Base 'Mojolicious::Controller', -signatures, -async_await;

# core
use Carp;
use Digest::SHA qw(sha256_hex);
use experimental qw(declared_refs refaliasing signatures);

# non core
use JSON::MaybeXS qw(decode_json encode_json);
use Ref::Util qw(is_arrayref is_hashref);

# local
use Pakket::Type::PackageQuery;
use Pakket::Utils qw(get_application_version);
use Pakket::Utils::DependencyBuilder;

## no critic [Modules::RequireEndWithOne, Lax::RequireEndWithTrueConst]

async sub get_index ($self) {
    my $snapshot_repo = $self->stash('snapshot_repo');
    my \@all_object_ids = $snapshot_repo->all_object_ids;
    return $self->render('json' => \@all_object_ids);
}

async sub get_item_or_index ($self) {
    my $snapshot_repo = $self->stash('snapshot_repo');
    my $id            = $self->param('id');

    return $self->get_index if !$id;

    if ($snapshot_repo->has_object($id)) {
        return $self->render(
            'json' => {
                'id'    => $id,
                'items' => decode_json($snapshot_repo->retrieve_content($id)),
                'type'  => $snapshot_repo->type,
                'path'  => $snapshot_repo->path,
            },
        );
    }

    return $self->render(
        'json' => {
            'error' => 'Not found',
            'id'    => $id,
        },
        'status' => 404,
    );
}

async sub post_ids_array ($self) {
    my $parcel_repo   = $self->stash('parcel_repo');
    my $snapshot_repo = $self->stash('snapshot_repo');

    my $dependency_builder = Pakket::Utils::DependencyBuilder->new(
        'spec_repo' => $self->stash('spec_repo'),
    );

    my \@ids = $self->req->json;
    @ids = sort @ids;

    my $checksum = sha256_hex($parcel_repo->path, @ids);

    my $result = [];

    if ($snapshot_repo->has_object($checksum)) {
        $result = decode_json($snapshot_repo->retrieve_content($checksum));
    } else {
        my @queries = map {
            Pakket::Type::PackageQuery->new_from_string($_, 'default_category' => $self->stash('default_category'))
        } @ids;
        eval {
            my $requirements = $dependency_builder->recursive_requirements(
                \@queries,
                'parcel_repo' => $parcel_repo,
                'phases'      => ['runtime'],
                'types'       => ['requires'],
            );
            $result = [map $_->id, $dependency_builder->validate_requirements($requirements)->@*];
            $snapshot_repo->store_content($checksum, encode_json($result));
            1;
        } or do {
            chomp (my $error = $@ || 'zombie error');
            $self->log->warn("unable to build dependency tree: $error");
            return $self->render(
                'json' => {
                    'error'   => $error,
                    'items'   => \@ids,
                    'version' => get_application_version,
                },
                'status' => 400,
            );
        };
    }

    return $self->render(
        'json' => {
            'id'      => $checksum,
            'items'   => $result,
            'version' => get_application_version,
        },
    );
}

1;

__END__

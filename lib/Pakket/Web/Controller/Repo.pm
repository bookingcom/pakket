package Pakket::Web::Controller::Repo;

# ABSTRACT: A web repo controller

use v5.28;
use namespace::autoclean;
use Mojo::Base 'Mojolicious::Controller', -signatures, -async_await;

use experimental qw(declared_refs refaliasing signatures);

use Pakket::Utils qw(get_application_version);
use Pakket::Utils::Package qw(parse_package_id);

## no critic [Modules::RequireEndWithOne, Lax::RequireEndWithTrueConst]

async sub get_filtered_index ($self) {
    my $repo = $self->stash('repo');
    my $id   = $self->param('id');

    my @result;
    if ($id) {
        my ($category, $name) = parse_package_id($id);
        \@result = $repo->all_object_ids_by_name($category, $name);
    } else {
        \@result = $repo->all_object_ids;
    }
    @result = sort @result;
    return $self->render(
        'json' => {
            'object_ids' => \@result,
            'type'       => $repo->type,
            'path'       => $repo->path,
            ('id' => $id) x !!$id,
        },
    );
}

async sub has_item ($self) {
    my $repo = $self->stash('repo');
    my $id   = $self->param('id');

    my $result = $repo->has_object($id);
    return $self->render(
        'json' => {
            'has_object' => $result,
            'type'       => $repo->type,
            'path'       => $repo->path,
            'id'         => $id,
        },
    );
}

async sub get_item ($self) {
    my $repo = $self->stash('repo');
    my $id   = $self->param('id');

    my $file;
    eval {
        $file = $repo->retrieve_content($id);
        1;
    } or do {
        return $self->reply->not_found;
    };

    my $format = 'bin';
    for ($repo->file_extension) {
        if ($_ eq 'json') {
            $format = 'json';
        } elsif ($_ eq 'tgz') {
            $format = 'gz';
        }
    }

    return $self->render(
        'data'   => $file,
        'format' => $format,
    );
}

sub put_item ($self) {
    my $repo    = $self->stash('repo');
    my $id      = $self->param('id');
    my $content = $self->req->body;

    defined && length
        or $self->reply->exception('Bad input')->rendered(400)
        for $id, $content;

    $repo->store_content($id, $content);
    return $self->render('json' => {'success' => 1});
}

sub delete_item ($self) {
    my $repo = $self->stash('repo');
    my $id   = $self->param('id');

    $repo->remove($id);

    return $self->render('json' => {'success' => 1});
}

1;

__END__

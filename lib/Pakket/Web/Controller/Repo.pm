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
    my ($id) = $self->_required_params($self->req->params->to_hash, 'id');

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

async sub get_json ($self) {
    my $repo = $self->stash('repo');

    my $content;
    eval {
        $content = $repo->retrieve_content($self->_required_params($self->req->params->to_hash, 'id'));
        1;
    } or do {
        return $self->reply->not_found;
    };

    return $self->render(
        'data'   => $content,
        'format' => 'json',
    );
}

async sub get_data ($self) {
    my $repo = $self->stash('repo');

    my $file;
    eval {
        $file = $repo->retrieve_location($self->_required_params($self->req->params->to_hash, 'id'));
        1;
    } or do {
        return $self->reply->not_found;
    };

    return $self->render(
        'data'   => $file->slurp_raw,
        'format' => 'bin',
    );
}

sub put_json ($self) {
    my $repo = $self->stash('repo');
    my \%payload = $self->req->json;

    $repo->store_content($self->_required_params(\%payload, 'id', 'content'));
    return $self->render('json' => {'success' => 1});
}

sub put_data ($self) {
    my $repo = $self->stash('repo');
    my ($id) = $self->_required_params($self->req->params->to_hash, 'id');

    $repo->store_content($id, $self->req->body);
    return $self->render('json' => {'success' => 1});
}

sub delete_item ($self) {
    my $repo = $self->stash('repo');

    $repo->remove($self->_required_params($self->req->params->to_hash, 'id'));

    return $self->render('json' => {'success' => 1});
}

sub _required_params ($self, $params, @required) {
    my %data = map {$_ => $params->{$_}} @required;

    defined $data{$_} && length $data{$_}
        or return $self->reply->exception("Bad input: $_")->rendered(400)
        for @required;

    my @result = @data{@required};
    return @result;
}

1;

__END__

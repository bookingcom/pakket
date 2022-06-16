package Pakket::Web;

# ABSTRACT: Mojolicious Web application

use v5.28;
use namespace::autoclean;
use Mojo::Base 'Mojolicious', -signatures;

use experimental qw(declared_refs refaliasing signatures);

# core
use Carp;
use List::Util qw(first uniq);

use Log::Any::Adapter;
use Log::Any::Adapter::Dispatch;
use Module::Runtime qw(use_module);
use YAML::XS        ();

# local
use Pakket::Config;
use Pakket::Repository;
use Pakket::Utils qw(shared_dir group_by flatten);

use constant {
    'ENV_PAKKET_WEB_CONFIG' => 'PAKKET_WEB_CONFIG',
};

has 'config_files' => sub ($self) {
    $self->config->{'config_files'} // ['~/.config/pakket-web', '~/.pakket-web', '/etc/pakket-web'];
};
has 'log_file' => sub ($self) {
    $self->config->{'log_file'} // '/var/log/pakket-web.log';
};

sub startup ($self) {
    $self->plugin('NotYAMLConfig');
    $self->secrets($self->config->{'secrets'}{'session'});

    push $self->renderer->paths->@*, $self->home->child('share/web/template');
    push $self->renderer->paths->@*, shared_dir('web') . '/template';
    push $self->static->paths->@*,   $self->home->child('share/web/public');
    push $self->static->paths->@*,   shared_dir('web') . '/public';

    $self->_setup_helpers();
    $self->_setup_plugins();

    my $pakket_config = Pakket::Config->new(
        'env_name' => ENV_PAKKET_WEB_CONFIG(),
        'paths'    => $self->config_files,
        'required' => 1,
    )->read_config;

    $self->_setup_logger($pakket_config);

    my \%repos
        = group_by(sub {$_->type}, map {Pakket::Repository->new_by_type($_->%*)} $pakket_config->{'repositories'}->@*);

    $self->_setup_legacy_routes($pakket_config, \%repos);
    $self->_setup_routes($pakket_config, \%repos);

    return;
}

sub _setup_helpers ($self) {
    $self->types->type('yaml' => 'application/yaml');
    $self->renderer->add_handler(
        'yaml' => sub ($renderer, $c, $output, $options) {
            delete $options->{'encoding'};                                     # Disable automatic encoding
            $$output = YAML::XS::Dump(delete $c->stash->{'yaml'});             # Encode data from stash value
        },
    );
    $self->hook(
        'before_render' => sub ($c, $args) {
            if (exists $args->{'yaml'} || exists $c->stash->{'yaml'}) {
                $args->{'handler'} = 'yaml';
                return;
            }

            my $template = $args->{'template'};
            ## Switch to JSON rendering if content negotiation allows it
            if ($template && $template eq 'exception') {
                return if !$c->accepts('json');
                $args->{'json'} = {'exception' => $c->stash('exception')};
            } elsif ($template && $template eq 'not_found') {
                return if !$c->accepts('json');
                $args->{'json'} = {'not_found' => $c->req->url};
            }
        },
    );
    return;
}

sub _setup_plugins ($self) {

    # $self->plugin('OpenAPI' => {'spec' => $self->static->file('api-v1.yaml')->path});

    return;
}

sub _setup_logger ($self, $config) {
    return if exists $config->{'log_file'} && !defined $config->{'log_file'};

    my $logfile = $config->{'log_file'} || $self->log_file();
    my $verbose = 0;
    my $plog    = use_module('Pakket::Log');
    Log::Any::Adapter->set('Dispatch',                       'dispatcher' => $plog->build_logger($verbose, $logfile));
    Log::Any::Adapter->set({'category' => qr/^CHI::Driver/}, 'Null');

    return;
}

sub _setup_legacy_routes ($self, $pakket_config, $repos_ref) {
    my \%repos = $repos_ref;

    foreach my $type (qw(spec source)) {
        !exists $repos{$type} || $repos{$type}->@* == 1
            or croak "Only one $type repo is allowed";
    }

    my $r = $self->routes;
    $r->get('/'       => 'status');
    $r->get('/status' => 'status');

    $r->get('/info')->to(
        'controller' => 'repos',
        'action'     => 'info',
        'repos'      => \%repos,
    );
    $r->get('/all_packages')->to(
        'controller' => 'repos',
        'action'     => 'all_packages',
        'repos'      => \%repos,
    );
    $r->get('/updates')->to(
        'controller' => 'repos',
        'action'     => 'get_updates',
        'repos'      => \%repos,
    );

    foreach my $repo (sort {$a->type cmp $b->type} flatten(values %repos)) {
        if ($repo->type eq 'snapshot') {
            if (exists $repos{'spec'} && exists $repos{'snapshot'}) {
                my %snapshot_params = (
                    'controller'       => 'snapshot',
                    'snapshot_repo'    => $repos{'snapshot'}[0],
                    'spec_repo'        => $repos{'spec'}[0],
                    'default_category' => $pakket_config->{'default_category'} // 'perl',
                );
                foreach my $path (uniq $repo->path, '/snapshots') {
                    my $sub = $r->any($path)->to(%snapshot_params);
                    $sub->get('/')->to('action' => 'get_item_or_index');
                    $sub->get('/:id')->to('action' => 'get_item_or_index');
                }
            }
        } else {
            my $sub = $r->any($repo->path)->to('controller' => 'repo');
            $sub->get('/')->to('action', 'get_filtered_index', 'repo', $repo);
            $sub->get('/all_object_ids')->to('action', 'get_filtered_index', 'repo', $repo);
            $sub->get('/all_object_ids_by_name')->to('action', 'get_filtered_index', 'repo', $repo);
            $sub->get('/all_object_ids_by_name/*id')->to('action', 'get_filtered_index', 'repo', $repo);
            $sub->get('/has_object')->to('action', 'has_item', 'repo', $repo);
            $sub->get('/has_object/*id')->to('action', 'has_item', 'repo', $repo);
            $sub->get('/retrieve/content')->to('action', 'get_json', 'repo', $repo);
            $sub->get('/retrieve/content/*id')->to('action', 'get_json', 'repo', $repo);
            $sub->get('/retrieve/location')->to('action', 'get_data', 'repo', $repo);
            $sub->get('/retrieve/location/*id')->to('action', 'get_data', 'repo', $repo);
            $sub->get('/id/*id')->to('action', 'get_filtered_index', 'repo', $repo);

            if ($pakket_config->{'allow_write'}) {
                ## $sub->put('/*id')->to('action', 'put_item', 'repo', $repo);
                $sub->post('/store/content')->to('action', 'put_json', 'repo', $repo);
                $sub->post('/store/content/*id')->to('action', 'put_json', 'repo', $repo);
                $sub->post('/store/location')->to('action', 'put_data', 'repo', $repo);
                $sub->post('/store/location/*id')->to('action', 'put_data', 'repo', $repo);
                ## $sub->delete('/*id')->to('action', 'delete_item', 'repo', $repo);
                $sub->get('/remove/location')->to('action', 'delete_item', 'repo', $repo);
                $sub->get('/remove/location/*id')->to('action', 'delete_item', 'repo', $repo);
            }

            if ($repo->type eq 'parcel' && exists $repos{'spec'} && exists $repos{'snapshot'}) {
                my %snapshot_params = (
                    'controller'       => 'snapshot',
                    'snapshot_repo'    => $repos{'snapshot'}[0],
                    'spec_repo'        => $repos{'spec'}[0],
                    'default_category' => $pakket_config->{'default_category'} // 'perl',
                );
                $sub->post('/snapshot')->to(
                    %snapshot_params,
                    'action'      => 'post_ids_array',
                    'parcel_repo' => $repo,
                );
            }
        }
    }

    return;
}

sub _setup_routes ($self, $pakket_config, $repos_ref) {
    return;
}

1;

__END__

package Pakket::Role::HasSourceRepo;

# ABSTRACT: Provide source repo support

use v5.22;
use Moose::Role;
use namespace::autoclean;

# core
use experimental qw(declared_refs refaliasing signatures);

# local
use Pakket::Repository::Source;

has 'source_repo' => (
    'is'      => 'ro',
    'isa'     => 'Pakket::Repository::Source',
    'lazy'    => 1,
    'default' => sub ($self) {
        Pakket::Repository::Source->new(
            'backend'   => $self->source_repo_backend,
            'log'       => $self->log,
            'log_depth' => $self->log_depth,
        );
    },
);

has 'source_repo_backend' => (
    'is'      => 'ro',
    'isa'     => 'PakketRepositoryBackend',
    'lazy'    => 1,
    'coerce'  => 1,
    'default' => sub ($self) {$self->config->{'repositories'}{'source'}},
);

sub add_source_for_package ($self, $package, $sources) {
    if ($self->source_repo->has_object($package->id) and !$self->overwrite) {
        $self->log->debugf('Package %s already exists in source repo (skipping)', $package->id);
        return;
    }

    #remove .git dir if it exists in sources
    $sources->child('.git')->remove_tree({'safe' => 0});

    $self->_upload_sources($package, $sources);

    return;
}

sub _upload_sources ($self, $package, $dir) {
    $self->log->debugf('uploading %s into source repo from %s', $package->name, "$dir");
    $self->source_repo->store_package($package, $dir);
    return;
}

1;

__END__

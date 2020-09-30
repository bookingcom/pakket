package Pakket::Controller::Scaffold::Native;

# ABSTRACT: Scffolding Native distributions

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

# core
use experimental qw(declared_refs refaliasing signatures);

# local
use Pakket::Helper::Download;
use Pakket::Type::Package;
use Pakket::Utils qw(
    env_vars
    expand_variables
    normalize_version
);

has 'type' => (
    'is'      => 'ro',
    'isa'     => 'Str',
    'default' => 'native',
);

with qw(
    Pakket::Role::CanApplyPatch
    Pakket::Role::HasConfig
    Pakket::Role::HasLog
    Pakket::Role::RunCommand
);

sub execute ($self, $query, $params) {
    my $release_info = {};
    $params->{'sources'} = $self->_fetch_source_for_package($query);

    $self->apply_patches($query, $params);

    my $meta = $query->has_meta ? $query->pakket_meta->scaffold // {} : {};
    my %env  = env_vars(
        $params->{'build_dir'},
        $meta->{'environment'},
        'bootstrap_dir' => $params->{'build_dir'},
        $params->%*,
    );

    $params->{'opts'} = {'env' => \%env};
    $params->{'pre'}  = expand_variables($meta->{'pre'},  \%env);
    $params->{'post'} = expand_variables($meta->{'post'}, \%env);

    local %ENV = %env;                                                         # keep all env changes locally
    $self->log->debug($_, '=', $ENV{$_}) foreach sort keys %ENV;

    $self->_run_pre_scaffold_commands($query, $params);

    return $self->_merge_release_info($query, $release_info, $params);
}

sub _fetch_source_for_package ($self, $query) {
    my $download = Pakket::Helper::Download->new(
        'name' => $query->name,
        'url'  => $query->source,
        $self->%{qw(log log_depth)},
    );
    return $download->to_dir;
}

sub _run_pre_scaffold_commands ($self, $query, $params) {
    $query->pakket_meta
        or return;

    if ($params->{'pre'}) {
        $self->run_command_sequence($params->{'sources'}, $params->{'opts'}, $params->{'pre'}->@*)
            or $self->croak('Failed to run pre-build commands');
    }

    if ($params->{'post'}) {
        $self->run_command_sequence($params->{'sources'}, $params->{'opts'}, $params->{'post'}->@*)
            or $self->croak('Failed to run post-build commands');
    }

    return;
}

sub _merge_release_info ($self, $query, $release_info, $params) {
    $query->{'release'} //= 1;
    $query->{'version'} = $release_info->{'version'} // $query->{'requirement'};

    # we had PackageQuery in $package now convert it to Package
    my %query_hash = $query->%*;
    delete @query_hash{qw(requirement conditions)};

    return Pakket::Type::Package->new(%query_hash);
}

sub bootstrap_prepare_modules ($self) {
    return +([], {});
}

sub bootstrap ($self, $controller, $modules, $requirements) {
    return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

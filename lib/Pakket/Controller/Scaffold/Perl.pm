package Pakket::Controller::Scaffold::Perl;

# ABSTRACT: Scffolding Perl distributions

use v5.22;
use Moose;
use MooseX::Clone;
use MooseX::StrictConstructor;
use namespace::autoclean;

# core
use experimental qw(declared_refs refaliasing signatures);

# non core
use JSON::MaybeXS qw(decode_json);
use Ref::Util qw(is_arrayref is_hashref);

# local
use Pakket::Helper::Download;
use Pakket::Type::PackageQuery;
use Pakket::Type::Package;
use Pakket::Utils qw(
    env_vars_scaffold
    env_vars_passthrough
    normalize_version
);

has 'type' => (
    'is'      => 'ro',
    'isa'     => 'Str',
    'default' => 'perl',
);

with qw(
    MooseX::Clone
    Pakket::Role::CanApplyPatch
    Pakket::Role::CanVisitPrereqs
    Pakket::Role::HasConfig
    Pakket::Role::HasLog
    Pakket::Role::Perl::BootstrapModules
    Pakket::Role::Perl::CanProcessSources
    Pakket::Role::Perl::CoreModules
    Pakket::Role::Perl::HasCpan
);

sub execute ($self, $query, $params) {
    my $release_info = $self->_get_release_info_for_package($query);

    $params->{'sources'} = $self->_fetch_source_for_package($query, $release_info);

    $self->apply_patches($query, $params);
    $self->_run_pre_scaffold_commands($query, $params);

    $self->_update_release_info($query, $release_info, $params);
    return $self->_merge_release_info($query, $release_info, $params);
}

sub _get_release_info_for_package ($self, $query) {
    if ($query->source && $query->source ne 'cpan') {
        return {
            'download_url' => $query->source,
        };
    }

    # check cpan for release info
    return $self->get_release_info($query);
}

sub _fetch_source_for_package ($self, $query, $release_info) {
    my $download_url = $self->_rewrite_download_url($release_info->{'download_url'})
        or $self->croak(q{Don't have download_url for:}, $query->name);

    my $download = Pakket::Helper::Download->new(
        'name' => $query->name,
        'url'  => $download_url,
        $self->%{qw(log log_depth)},
    );
    return $download->to_dir;
}

sub _rewrite_download_url ($self, $download_url) {
    my $rewrite = $self->config->{'perl'}{'metacpan'}{'rewrite_download_url'};
    is_hashref($rewrite)
        or return $download_url;
    my ($from, $to) = @{$rewrite}{qw(from to)};
    return ($download_url =~ s{$from}{$to}r);
}

sub _run_pre_scaffold_commands ($self, $query, $params) {
    $query->pakket_meta
        or return;

    my $meta = $query->pakket_meta->scaffold // {};
    my $env  = {env_vars_passthrough(), env_vars_scaffold($params), %{$meta->{'environment'} // {}}};
    $self->log->debug($_, '=', $env->{$_}) foreach sort keys $env->%*;

    my $opts = {'env' => $env};

    if ($meta->{'pre'}) {
        $self->run_command_sequence($params->{'sources'}, $opts, $meta->{'pre'}->@*)
            or $self->croak('Failed to run pre-build commands');
    }

    if (!$meta->{'skip'}{'dzil'} && ($query->source && $query->source ne 'cpan')) {
        $self->process_dist_ini($query, $opts, $params);
    }
    if (!$meta->{'skip'}{'dist'} && ($query->source && $query->source ne 'cpan')) {
        $self->process_makefile_pl($query, $opts, $params);
    }

    if ($meta->{'post'}) {
        $self->run_command_sequence($params->{'sources'}, $opts, $meta->{'post'}->@*)
            or $self->croak('Failed to run post-build commands');
    }

    return;
}

sub _update_release_info ($self, $query, $release_info, $params) {
    if ($query->source) {
        $self->_load_pakket_json($params->{'sources'});

        my $found = 0;
        foreach my $name (qw(META.json META.yml)) {
            my $file = $params->{'sources'}->child($name);
            if ($file->is_file) {
                my $meta = $self->meta_load($file);
                $release_info->{'version'} && $release_info->{'version'} ne $meta->version
                    and $self->croak(q{Version in META.json doesn't match version of release info});
                $release_info->{'version'} = $meta->version;
                $release_info->{'prereqs'} = $meta->effective_prereqs->as_string_hash;
                $found                     = 1;
                last;
            }
        }

        $found
            or $self->log->warn(q{Can't find META.json or META.yml in sources});
    }

    return;
}

sub _merge_release_info ($self, $query, $release_info, $params) {
    $release_info->{'prereqs'}
        and $self->log->info('Preparing prereqs for:', $query->id)
        and $self->_filter_prereqs($query, $release_info->{'prereqs'});

    $query->{'source'} = $release_info->{'download_url'} if $release_info->{'download_url'};
    $query->{'version'} && $release_info->{'version'} && $query->{'version'} ne $release_info->{'version'}
        and $self->croakf(q{Version(%s) doesn't match sources(%s)}, $query->{'version'}, $release_info->{'version'});
    $query->{'version'} = normalize_version($release_info->{'version'}) if $release_info->{'version'};
    $query->{'release'} //= 1;

    # we had PackageQuery in $package now convert it to Package
    my %query_hash = $query->%*;
    delete @query_hash{qw(requirement conditions)};

    return Pakket::Type::Package->new(%query_hash);
}

sub _filter_prereqs ($self, $query, $prereqs) {
    my %result;
    $self->visit_prereqs(
        $prereqs,
        sub ($phase, $type, $name, $requirement) {
            $self->_should_skip_module($name)
                and return;

            my $distribution = $self->determine_distribution($name);
            if (exists $self->cpan->known_incorrect_dependencies->{$query->name}{$distribution}) {
                $self->log->infof(q{Skipping %s (known 'bad' dependency for %s)}, $distribution, $query->name);
                return;
            }

            if (!exists $result{$phase}{$type}{"perl/$distribution"}) {
                $self->log->infof('%s %12s %10s: %s=%s', $query->id, $phase, $type, $distribution, $requirement);
                $result{$phase}{$type}{"perl/$distribution"} = ($requirement || '0');
            }
        },
    );

    $query->inject_prereqs(\%result);

    return;
}

sub _should_skip_module ($self, $module) {
    if (should_skip_core_module($module)) {
        $self->log->debug('skipping (core module, not dual-life):', $module);
        return 1;
    }

    if (exists $self->cpan->known_modules_to_skip->{$module}) {
        $self->log->debug(q{skipping (known 'bad' module for configuration):}, $module);
        return 1;
    }

    return 0;
}

# Packet.json should be in root directory of package, near META.json
# It keeps some settings which we are missing in META.json.
sub _load_pakket_json ($self, $dir) {
    my $pakket_json = $dir->child('Pakket.json');

    $pakket_json->exists
        or return;

    $self->log->debug('found Pakket.json in:', $dir);

    my $data = decode_json($pakket_json->slurp_utf8);

    # Using to map module->distribution for local not-CPAN modules
    if ($data->{'module_to_distribution'}) {
        for my $module_name (keys $data->{'module_to_distribution'}->%*) {
            my $distribution = $data->{'module_to_distribution'}{$module_name};
            $self->distribution->{$module_name} = $distribution;
        }
    }
    return $data;
}

sub bootstrap_prepare_modules ($self) {
    my @modules      = $self->bootstrap_modules->@*;
    my %requirements = map {                                                   # no tidy
        my $q = Pakket::Type::PackageQuery->new_from_string(
            $_,
            'default_category' => 'perl',
            'as_prereq'        => 0,
        );
        +($q->short_name, $q)
    } @modules;

    return +(\@modules, \%requirements);
}

sub bootstrap ($self, $controller, $modules, $requirements) {
    $requirements->%*
        or return;

    my @phases = qw(configure build runtime test);
    my @types  = qw(requires);

    $controller->clone(
        'no_continue' => 1,
    )->_process_queries(
        [$requirements->@{$modules->@*}],
        'phases' => \@phases,
        'types'  => \@types,
    );

    return;
}

before [qw(_filter_prereqs)] => sub ($self, @) {
    return $self->log_depth_change(+1);
};

after [qw(_filter_prereqs)] => sub ($self, @) {
    return $self->log_depth_change(-1);
};

__PACKAGE__->meta->make_immutable;

1;

__END__

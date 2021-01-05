package Pakket::Helper::Cpan;

# ABSTRACT: A Perl CPAN helper class

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

# core
use Carp;
use experimental qw(declared_refs refaliasing signatures);

# non core
use CPAN::DistnameInfo;
use CPAN::Meta;
use JSON::MaybeXS qw(decode_json encode_json);
use Module::Runtime qw(require_module);
use Parse::CPAN::Packages::Fast;
use Path::Tiny;
use Ref::Util qw(is_arrayref is_hashref);

# local
use Pakket::Helper::Versioner;
use Pakket::Helper::Download;
use Pakket::Utils qw(shared_dir);

with qw(
    Pakket::Role::CanFilterRequirements
    Pakket::Role::HasLog
    Pakket::Role::HasConfig
    Pakket::Role::HttpAgent
);

has 'metacpan_api' => (
    'is'      => 'ro',
    'isa'     => 'Str',
    'lazy'    => 1,
    'builder' => '_build_metacpan_api',
);

has 'versioner' => (
    'is'      => 'ro',
    'isa'     => 'Pakket::Helper::Versioner',
    'lazy'    => 1,
    'default' => sub {Pakket::Helper::Versioner->new('type' => 'Perl')},
);

has 'latest_distributions' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'lazy'    => 1,
    'builder' => '_build_latest_distributions',
);

has 'cpan_02packages' => (
    'is'      => 'ro',
    'isa'     => 'Parse::CPAN::Packages::Fast',
    'lazy'    => 1,
    'default' => sub ($self) {Parse::CPAN::Packages::Fast->new($self->_get_cpan_02packages_file())},
);

has 'cpan_02packages_file' => (
    'is'      => 'ro',
    'isa'     => 'Maybe[Str]',
    'lazy'    => 1,
    'builder' => '_build_cpan_02packages_file',
);

has 'distributions_cache' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'default' => sub {+{}},
);

has 'known_incorrect_name_fixes' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'builder' => '_build_known_incorrect_name_fixes',
);

has 'known_incorrect_version_fixes' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'builder' => '_build_known_incorrect_version_fixes',
);

has 'known_incorrect_dependencies' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'builder' => '_build_known_incorrect_dependencies',
);

has 'known_modules_to_skip' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'builder' => '_build_known_modules_to_skip',
);

sub BUILDARGS ($class, %args) {
    return Pakket::Role::HasLog->BUILDARGS(%args); ## no critic [Modules::RequireExplicitInclusion]
}

sub meta_load ($self, $file) {
    return CPAN::Meta->load_file($file);
}

sub get_release_info ($self, $query) {
    my %latest_dist_release = $self->_get_latest_release_info_for_distribution($query->name);
    if (%latest_dist_release) {
        my ($version, $release_info) = $self->select_best_version_from_cache($query, \%latest_dist_release);
        if ($version && defined $release_info->{'download_url'}) {
            return $release_info;
        }
        $self->log->debugf(q{latest version of %s is %s. doesn't satisfy requirements, checking older versions},
            $query->name, (keys %latest_dist_release)[0]);
    }

    my \%all_dist_releases = $self->_get_all_releases_for_distribution($query->name);

    my ($version, $release_info) = $self->select_best_version_from_cache($query, \%all_dist_releases);

    $version = $self->known_incorrect_version_fixes->{$query->name} // $version;

    if (!$version) {
        croak(
            sprintf (
                'Cannot find a suitable version for %s, available: %s',
                $query->id, join (', ', keys %all_dist_releases),
            ),
        );
    }

    return {
        'distribution' => $query->name,
        'version'      => $version,
        $release_info->%{qw(download_url prereqs)},
    };
}

sub determine_distribution ($self, $module_name) {
    if (exists $self->known_incorrect_name_fixes->{$module_name}) {
        $self->log->debug('fixing module following known_incorrect_name_fixes:', $module_name);
        $module_name = $self->known_incorrect_name_fixes->{$module_name};
    }

    exists $self->distributions_cache->{$module_name}                          # check if we've already seen it
        and $self->log->trace('found distribution in cache for:', $module_name)
        and return $self->distributions_cache->{$module_name};

    $self->log->trace('detecting distribution name for:', $module_name);

    # check if we can get it from 02packages
    my $distribution = $self->_get_distribution_02packages($module_name);

    # fallback: metacpan check
    $distribution ||= $self->_get_distribution($module_name);

    $distribution
        or croak($self->log->critical('Unable to detect distribution name for:', $module_name));

    $self->log->debugf(q{distribution name for '%s': %s}, $module_name, $distribution);
    $self->distributions_cache->{$module_name} = $distribution;

    return $distribution;
}

sub outdated ($self, $cache) {
    my \%cpan_dist = $self->latest_distributions;

    my %result;
    foreach my $short_name (sort keys $cache->%*) {
        if (exists $cpan_dist{$short_name}) {
            my @versions       = keys $cache->{$short_name}->%*;
            my $cpan_version   = $cpan_dist{$short_name}{'version'};
            my $latest_version = $self->versioner->select_latest(\@versions);

            if ($self->versioner->compare_version($latest_version, $cpan_version) < 0) {
                $result{$short_name} = {
                    'version'      => $latest_version,
                    'cpan_version' => $cpan_version,
                };
            }
        }
    }

    return \%result;
}

sub _get_distribution_02packages ($self, $module_name) {
    my $distribution_name;

    $self->cpan_02packages
        and $distribution_name = $self->_get_distribution_from_02packages_file($module_name);

    $distribution_name ||= $self->_get_distribution_from_02packages_api($module_name);

    $self->cpan_02packages
        or $distribution_name ||= $self->_get_distribution_from_02packages_file($module_name);    # fallback to cpan_02packages

    return $distribution_name;
}

sub _get_distribution_from_02packages_file ($self, $module_name) {
    my $mod = $self->cpan_02packages->package($module_name)
        or return;
    return $mod->distribution->dist;
}

sub _get_distribution_from_02packages_api ($self, $module_name) {
    my $distribution_name;
    eval {
        my $url = $self->metacpan_api . '/package/' . $module_name;
        $self->log->debugf('requesting information about package %s (%s)', $module_name, $url);
        my $res = $self->ua->get($url);

        $res->{'status'} != 200
            and croak($self->log->critical('Cannot fetch:', $url));

        my $content = decode_json($res->{'content'});
        $distribution_name = $content->{'distribution'};
        1;
    } or do {
        chomp (my $error = $@ || 'zombie error');
        $self->log->warn($error);
    };
    return $distribution_name;
}

sub _get_distribution ($self, $module_name) {
    my $distribution_name;
    eval {
        my $url = join ('/', $self->metacpan_api, 'module', $module_name);
        $self->log->debugf('requesting information about module %s (%s)', $module_name, $url);
        my $response = $self->ua->get($url);

        $response->{'status'} != 200
            and croak($self->log->critical('Cannot fetch:', $url));

        my $content = decode_json $response->{'content'};
        $distribution_name = $content->{'distribution'};
        1;
    } or do {
        chomp (my $error = $@ || 'Zombie error');
        $self->log->warn($error);
    };

    # fallback 2: check if name matches a distribution name
    if (!$distribution_name) {
        eval {
            my $release_name = $module_name =~ s{::}{-}rgsmx;
            my $url          = $self->metacpan_api . '/release';
            $self->log->debug("Requesting information about distribution $release_name ($url)");
            my $res = $self->ua->post($url, +{'content' => $self->_get_is_dist_name_query($release_name)});
            $res->{'status'} != 200
                and croak($self->log->critical('Cannot fetch:', $url));

            my $res_body = decode_json $res->{'content'};
            $res_body->{'hits'}{'total'} > 0
                or croak("Cannot find distribution for module: $module_name");

            1;
        } or do {
            chomp (my $error = $@ || 'Zombie error');
            $self->log->warn($error);
        };
    }

    return $distribution_name;
}

sub _get_latest_release_info_for_distribution ($self, $distribution_name) {
    my $url = join ('/', $self->metacpan_api, 'release', $distribution_name);
    $self->log->debugf('requesting release info for latest version of %s (%s)', $distribution_name, $url);
    my $res = $self->ua->get($url);
    if ($res->{'status'} != 200) {
        $self->log->warnf('Failed receive from %s, status: %s, reason: %s', $url, $res->{'status'}, $res->{'reason'});
        return;
    }

    my $content = decode_json($res->{'content'});
    my $version = $self->known_incorrect_version_fixes->{$distribution_name} // $content->{'version'};

    return +(
        $version => {
            'distribution' => $distribution_name,
            'version'      => $version,
            'download_url' => $content->{'download_url'},
            'prereqs'      => $content->{'metadata'}{'prereqs'},
        },
    );
}

sub _get_all_releases_for_distribution ($self, $distribution_name) {
    my $url = join ('/', $self->metacpan_api, 'release');
    $self->log->debugf('requesting release info for all versions of %s (%s)', $distribution_name, $url);
    my $res = $self->ua->post($url, +{'content' => $self->_get_release_query($distribution_name)});
    if ($res->{'status'} != 200) {
        croak(
            $self->log->criticalf(
                q{Can't find any release for %s from %s, status: %s, reason: %s},
                $distribution_name, $url, $res->{'status'}, $res->{'reason'},
            ),
        );
    }

    my $content = decode_json($res->{'content'});
    is_arrayref($content->{'hits'}{'hits'})
        or croak($self->log->critical(q{Can't find any release for:}, $distribution_name));

    ## get the matching version according to the spec
    #my @valid_versions;
    #for my $v (keys %all_dist_releases) {
    #eval {
    #version->parse($v);
    #push @valid_versions => $v;
    #1;
    #} or do {
    #my $err = $@ || 'zombie error';
    #$self->log->warnf('[VERSION ERROR] distribution: %s, version: %s, error: %s', $query->name, $v, $err);
    #};
    #}
    #@valid_versions = sort {$self->versioner->compare($a, $b)} @valid_versions;

    my %all_releases = map {
        my $v = $_->{'fields'}{'version'};
        (is_arrayref($v) ? $v->[0] : $v) => {
            'prereqs'      => $_->{'_source'}{'metadata'}{'prereqs'},
            'download_url' => $_->{'_source'}{'download_url'},
        }
    } $content->{'hits'}{'hits'}->@*;

    return \%all_releases;
}

sub _get_release_query ($self, $distribution_name) {
    return encode_json({
            'query' => {
                'bool' => {
                    'must' => [
                        {'term' => {'distribution' => $distribution_name}},

                        # { 'terms' => { 'status' => [qw(cpan latest)] } }
                    ],
                },
            },
            'fields'  => [qw(version)],
            '_source' => [qw(metadata.prereqs download_url)],
            'size'    => 999,
        },
    );
}

sub _get_is_dist_name_query ($self, $name) {
    return encode_json({
            'query'  => {'bool' => {'must' => [{'term' => {'distribution' => $name}}]}},
            'fields' => [qw(distribution)],
            'size'   => 0,
        },
    );
}

sub _build_metacpan_api ($self) {
    return
           $ENV{'PAKKET_METACPAN_API'}
        || $self->config->{'perl'}{'metacpan_api'}
        || 'https://fastapi.metacpan.org';
}

sub _get_cpan_02packages_file ($self) {
    if ($self->cpan_02packages_file) {
        $self->log->info('Using 02packages file:', $self->cpan_02packages_file);
        my $file = path($self->cpan_02packages_file);

        $file->is_file
            and return $file;
    }

    my $file = Pakket::Helper::Download->new(
        'name' => '02packages.details.txt',
        'url'  => 'https://cpan.metacpan.org/modules/02packages.details.txt',
    )->to_file;

    $self->cpan_02packages_file
        and $file->copy($self->cpan_02packages_file);

    return $file;
}

sub _build_cpan_02packages_file ($self) {
    return shared_dir('02packages.details.txt')->stringify;
}

sub _build_latest_distributions ($self) {
    my %cpan_dist;
    foreach my $dist ($self->cpan_02packages->distributions) {
        $dist->{'dist'} && $dist->{'version'}
            or next;

        my $short_name = "perl/$dist->{'dist'}";
        if (exists $cpan_dist{$short_name}) {
            eval {
                if ($self->versioner->compare_version($cpan_dist{$short_name}{'version'}, $dist->{'version'}) < 0) {
                    $cpan_dist{"perl/$dist->{'dist'}"} = $dist;
                }
                1;
            } or do {
                my $error = $@ || 'zombie error';
                carp "Build latest distributions error $error for $dist->{'dist'}";
            };
        } else {
            $cpan_dist{$short_name} = $dist;
        }
    }
    return \%cpan_dist;
}

sub _build_known_incorrect_name_fixes ($self) {
    return {
        'App::Fatpacker'                                                     => 'App::FatPacker',
        'Test::YAML::Meta::Version'                                          => 'Test::CPAN::Meta::YAML',     # not sure about this
        'Net::Server::SS::Prefork'                                           => 'Net::Server::SS::PreFork',
        'Data::Sah::Coerce::perl::To_date::From_float::epoch'                => 'Data::Sah::Coerce',
        'Data::Sah::Coerce::perl::To_date::From_obj::datetime'               => 'Data::Sah::Coerce',
        'Data::Sah::Coerce::perl::To_date::From_obj::time_moment'            => 'Data::Sah::Coerce',
        'Data::Sah::Coerce::perl::To_date::From_str::iso8601'                => 'Data::Sah::Coerce',
        'Data::Sah::Coerce::perl::To_str::From_str::normalize_perl_distname' => 'Data::Sah::Coerce',
        'Data::Sah::Coerce::perl::To_str::From_str::normalize_perl_modname'  => 'Data::Sah::Coerce',
        'Data::Sah::Coerce::perl::To_str::From_str::strip_slashes'           => 'Data::Sah::Coerce',
        'Data::Sah::Compiler::perl::TH::array'                               => 'Data::Sah',
        'Data::Sah::Compiler::perl::TH::bool'                                => 'Data::Sah',
        'Data::Sah::Compiler::perl::TH::date'                                => 'Data::Sah',
        'Data::Sah::Compiler::perl::TH::int'                                 => 'Data::Sah',
        'Data::Sah::Compiler::perl::TH::re'                                  => 'Data::Sah',
        'Data::Sah::Compiler::perl::TH::str'                                 => 'Data::Sah',
        'URI::_generic'                                                      => 'URI',
        %{$self->config->{'perl'}{'scaffold'}{'known_incorrect_name_fixes'} // {}},
    };
}

sub _build_known_incorrect_version_fixes ($self) {
    return {
        'Data-Swap'             => '0.08',
        'Encode-HanConvert'     => '0.35',
        'ExtUtils-Constant'     => '0.23',
        'Frontier-RPC'          => '0.07',
        'IO-Capture'            => '0.05',
        'Memoize-Memcached'     => '0.04',
        'Statistics-Regression' => '0.53',
        %{$self->config->{'perl'}{'scaffold'}{'known_incorrect_version_fixes'} // {}},
    };
}

sub _build_known_incorrect_dependencies ($self) {
    return {
        'Module-Install' => {
            'libwww-perl' => 1,
            'PAR-Dist'    => 1,
        },
        'libwww-perl' => {
            'NTLM' => 1,
        },
        %{$self->config->{'perl'}{'scaffold'}{'known_incorrect_dependencies'} // {}},
    };
}

sub _build_known_modules_to_skip ($self) {
    return {
        'HTTP::GHTTP'              => 1,
        'Test2::Tools::PerlCritic' => 1,
        'Test::YAML::Meta'         => 1,
        'Text::MultiMarkdown::XS'  => 1,                                       # ADOPTME
        'inc::MMPackageStash'      => 1,                                       # unable to find on cpan
        'perl'                     => 1,
        'perl_mlb'                 => 1,
        'tinyperl'                 => 1,
        %{$self->config->{'perl'}{'scaffold'}{'known_modules_to_skip'} // {}},
    };
}

__PACKAGE__->meta->make_immutable;

1;

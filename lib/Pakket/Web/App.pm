package Pakket::Web::App;

# ABSTRACT: The Pakket web application

use v5.22;
use Dancer2 'appname'              => 'Pakket::Web';
use namespace::autoclean '-except' => 'to_app';

# core
use Carp;
use List::Util qw(first);
use experimental qw(declared_refs refaliasing signatures);

# non core
use Log::Any qw($log);
use Module::Runtime qw(use_module);
use Path::Tiny;

# local
use Pakket::Web::Repo;
use Pakket::Utils qw(get_application_version shared_dir);
use Pakket::Config;

use constant {
    'PATHS' =>
        [$ENV{'PAKKET_WEB_CONFIG'} || (), '~/.config/pakket-web.json', '~/.pakket-web.json', '/etc/pakket-web.json'],
    'DIRNAME' => shared_dir('views') || path(__FILE__)->sibling('views'),
};

set 'content_type' => 'application/json';

## no critic [Modules::RequireExplicitInclusion]
sub status_page {
    set 'content_type' => 'text/html';
    set 'auto_page'    => 1;
    set 'views'        => DIRNAME()->stringify;

    return template 'status';
}

## no critic [Subroutines::ProhibitExcessComplexity]
sub setup ($class, $config_file = undef) {
    my $cpan = use_module('Pakket::Helper::Cpan')->new;

    my $config = Pakket::Config->new(
        'required' => 1,
        'env_name' => 'PAKKET_WEB_CONFIG',
        'paths'    => ['~/.config/pakket-web', '/etc/pakket-web'],
    )->read_config;

    my $spec_repo;
    my @repos;
    foreach my $repo_config ($config->{'repositories'}->@*) {
        my $repo = Pakket::Web::Repo->create($repo_config);
        push (
            @repos,
            {
                'repo_config' => $repo_config,
                'repo'        => $repo,
            },
        );

        if (!$spec_repo && $repo_config->{'type'} eq 'spec') {
            $spec_repo = $repo;
        }
    }

    if ($spec_repo && defined $config->{'snapshot'}) {
        use_module('Pakket::Web::Snapshot')->expose($config->{'snapshot'}, $spec_repo, @repos);
    }

    # status page is accessible via / and /status
    get '/'       => \&status_page;
    get '/status' => \&status_page;

    # status page handler
    get '/info' => sub {
        set 'content_type' => 'application/json';
        my @repositories = map {{'type' => $_->{'type'}, 'path' => $_->{'path'}}} $config->{'repositories'}->@*;
        return encode_json({
                'version'      => get_application_version(),
                'repositories' => \@repositories,
            },
        );
    };

    get '/updates' => sub {
        set 'content_type' => 'application/json';

        my @result;
        foreach my $repo (@repos) {
            my $type = $repo->{'repo_config'}{'type'};
            if ($type eq 'spec') {
                my \%cache    = $repo->{'repo'}->all_objects_cache;
                my \%outdated = $cpan->outdated(\%cache);
                @result = map {"$_=$outdated{$_}{'cpan_version'}"} sort keys %outdated;
                last;
            }
        }

        return encode_json({'items' => \@result});
    };

    ## no critic [ControlStructures::ProhibitDeepNests]
    get '/all_packages' => sub {
        set 'content_type' => 'application/json';

        my %all_packages;
        for my $repo (@repos) {
            for my $package ($repo->{'repo'}->all_object_ids->@*) {
                $all_packages{$package}{$repo} = 1;
            }
        }

        my %result;
        foreach my $repo (@repos) {
            my $type = $repo->{'repo_config'}{'type'};
            my ($p1, $p2, $p3) = split (m{/}, $repo->{'repo_config'}{'path'});

            if ($type eq 'spec') {                                             # here detect outdated packages
                my \%cache              = $repo->{'repo'}->all_objects_cache;
                my \%outdated           = $cpan->outdated(\%cache);
                my \%cpan_distributions = $cpan->latest_distributions;
                foreach my $short_name (keys %cache) {
                    my \%versions = $cache{$short_name};
                    my $name = $short_name =~ s{.* /}{}xmsgr;
                    foreach my $version (keys %versions) {
                        my \%releases = $versions{$version};
                        foreach my $release (keys %releases) {
                            my $id = "$short_name=$version:$release";
                            exists $cpan_distributions{$short_name}
                                and $result{$id}{'cpan'} = 1;
                            exists $outdated{$short_name} and do {
                                $result{$id}{'cpan_version'} = $outdated{$short_name}{'cpan_version'};
                            };
                        }
                    }
                }
            }

            if ($type eq 'spec' or $type eq 'source') {
                for my $id (keys %all_packages) {
                    $result{$id}{$type} = $all_packages{$id}{$repo} // 0;
                }
            } else {
                for my $id (keys %all_packages) {
                    $result{$id}{$p3}{$p2} = $all_packages{$id}{$repo} // 0;
                }
            }
        }

        return encode_json(\%result);
    };

    # manually defining static resources
    get '/css/error.css' => sub {
        set 'content_type' => 'text/css';
        set 'auto_page'    => 1;
        set 'views'        => DIRNAME()->stringify;
        template 'css/error';
    };

    get '/css/styles.css' => sub {
        set 'content_type' => 'text/css';
        set 'auto_page'    => 1;
        set 'views'        => DIRNAME()->stringify;
        template 'css/styles';
    };

    get '/js/app.js' => sub {
        set 'content_type' => 'text/javascript';
        set 'auto_page'    => 1;
        set 'views'        => DIRNAME()->stringify;
        template 'js/app';
    };

    get '/favicon.ico' => sub {
        set 'content_type' => 'image/x-icon';
        return send_file(DIRNAME()->child('favicon.ico')->stringify, system_path => 1);
    };

    get '/png/:name' => sub {
        set 'content_type' => 'image/png';
        return send_file(DIRNAME()->child('png', params->{name})->stringify, system_path => 1);
    };

    return;
}

1;

__END__

package Pakket::Web::App;

# ABSTRACT: The Pakket web application

use v5.22;
use Dancer2 'appname'              => 'Pakket::Web';
use namespace::autoclean '-except' => 'to_app';

# core
use Carp;
use experimental qw(declared_refs refaliasing signatures);

# non core
use List::Util qw(first);
use Log::Any qw($log);
use Module::Runtime qw(use_module);
use Path::Tiny;

# local
use Pakket::Web::Repo;
use Pakket::Utils qw(get_application_version);

use constant {
    'PATHS' =>
        [$ENV{'PAKKET_WEB_CONFIG'} || (), '~/.config/pakket-web.json', '~/.pakket-web.json', '/etc/pakket-web.json'],
    'DIRNAME' => dirname(__FILE__),
};

set 'content_type' => 'application/json';

sub status_page {
    set 'content_type' => 'text/html';
    set 'auto_page'    => 1;
    set 'views'        => path(DIRNAME(), 'views')->stringify;

    return template 'status';
}

sub setup ($class, $config_file = undef) {
    $config_file //= first {path($_)->exists} PATHS()->@*
        or croak(
        $log->fatal(
            'Please specify a config file: PAKKET_WEB_CONFIG, ~/.config/pakket-web.json, or /etc/pakket-web.json'),
        );

    my $config = decode_json(path($config_file)->slurp_utf8);

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

    $spec_repo && defined $config->{'snapshot'}
        and use_module('Pakket::Web::Snapshot')->expose($config->{'snapshot'}, $spec_repo, @repos);

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

    get '/all_packages' => sub {
        set 'content_type' => 'application/json';
        my %packages;
        for my $repo (@repos) {
            my \@ids = $repo->{'repo'}->all_object_ids();
            for my $package (@ids) {
                $packages{$package}{$repo} = 1;
            }
        }
        my %output;
        for my $repo (@repos) {
            my $type = $repo->{'repo_config'}{'type'};
            if ($type eq 'spec' or $type eq 'source') {
                for my $package (keys %packages) {
                    $output{$package}{$type} = $packages{$package}{$repo} // 0;
                }
            } else {
                my ($p1, $p2, $p3) = split (m{/}, $repo->{'repo_config'}{'path'});
                for my $package (keys %packages) {
                    $output{$package}{$p3}{$p2} = $packages{$package}{$repo} // 0;
                }
            }
        }
        my @sorted_output;
        for my $package (sort keys %output) {
            push @sorted_output, [$package, $output{$package}];
        }

        return encode_json(\@sorted_output);
    };

    # manually defining static resources
    get '/css/error.css' => sub {
        set 'content_type' => 'text/css';
        set 'auto_page'    => 1;
        set 'views'        => path(DIRNAME(), 'views')->stringify;
        template 'css/error';
    };

    get '/css/styles.css' => sub {
        set 'content_type' => 'text/css';
        set 'auto_page'    => 1;
        set 'views'        => path(DIRNAME(), 'views')->stringify;
        template 'css/styles';
    };

    get '/js/app.js' => sub {
        set 'content_type' => 'text/javascript';
        set 'auto_page'    => 1;
        set 'views'        => path(DIRNAME(), 'views')->stringify;
        template 'js/app';
    };

    get '/favicon.ico' => sub {
        return send_file(path(DIRNAME(), 'views', 'favicon.ico')->stringify, 'content_type' => 'image/x-icon');
    };

    return;
}

1;

__END__

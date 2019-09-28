package Pakket::Web::App;
# ABSTRACT: The Pakket web application

use v5.22;
use Dancer2 0.204001 'appname' => 'Pakket::Web'; # decode_json
use Log::Any qw< $log >;
use List::Util qw< first >;
use Path::Tiny ();
use Pakket::Web::Repo;
use constant {
    'PATHS' => [
        $ENV{'PAKKET_WEB_CONFIG'} || (),
        '~/.pakket-web.json',
        '/etc/pakket-web.json',
    ],
};

# TODO: while testing I see, that content type is not really
# propagated into endpoints every time
set content_type => 'application/json';

sub status_page {
    set content_type => 'text/html';
    set auto_page    => 1;
    set views        => path( dirname(__FILE__), 'views' );
    template 'status';
}

sub setup {
    my ( $class, $config_file ) = @_;

    $config_file //= first { Path::Tiny::path($_)->exists } @{ PATHS() }
        or die $log->fatal(
            'Please specify a config file: PAKKET_WEB_CONFIG, '
          . '~/.pakket-web.json, or /etc/pakket-web.json.',
        );

    my $config = decode_json( Path::Tiny::path($config_file)->slurp_utf8 );

    my @repos;
    foreach my $repo_config ( @{ $config->{'repositories'} } ) {
        my $repo = Pakket::Web::Repo->create($repo_config);
        push @repos, {'repo_config' => $repo_config, 'repo' => $repo};
    }

    # status page handler
    get '/info' => sub {
        set content_type => 'application/json';
        my @repositories =  map { { 'type' => $_->{'type'},
                                    'path' => $_->{'path'} } }
                                @{ $config->{'repositories'} };
        return encode_json({
                'version' => $Pakket::Web::App::VERSION,
                'repositories' => [@repositories],
                });
    };

    get '/all_packages' => sub {
        set content_type => 'application/json';
        my %packages;
        for my $repo (@repos) {
            my $ids = $repo->{'repo'}->all_object_ids();
            for my $package (@{$ids}) {
                $packages{$package}{$repo}=1;
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
                my ($p1,$p2,$p3) = split '/', $repo->{'repo_config'}{'path'};
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

    # status page is accessible via / and /status
    get '/' => \&status_page;
    get '/status' => \&status_page;

    # manually defining static resources
    # TODO: change extension, use some sort of auto-detection
    get '/css/styles.css' => sub {
      set content_type => 'text/css';
      set auto_page => 1;
      my $dirname = dirname(__FILE__);
      set views => path($dirname, 'views');
      template 'css/styles';
    };
    get '/js/app.js' => sub {
      set content_type => 'text/javascript';
      set auto_page => 1;
      my $dirname = dirname(__FILE__);
      set views => path($dirname, 'views');
      template 'js/app';
    };

}

1;

__END__

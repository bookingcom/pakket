package Pakket::Web::App;
# ABSTRACT: The Pakket web application

use Dancer2 0.204001 'appname' => 'Pakket::Web'; # decode_json
use Log::Any qw< $log >;
use List::Util qw< first uniq >;
use Path::Tiny ();
use Pakket::Web::Repo;
use constant {
    'PATHS' => [
        $ENV{'PAKKET_WEB_CONFIG'} || (),
        '~/.pakket-web.json',
        '/etc/pakket-web.json',
    ],
};

set content_type => 'application/json';

sub setup {
    my ( $class, $config_file ) = @_;

    $config_file //= first { Path::Tiny::path($_)->exists } @{ PATHS() }
        or die $log->fatal(
            'Please specify a config file: PAKKET_WEB_CONFIG, '
          . '~/.pakket-web.json, or /etc/pakket-web.json.',
        );

    my $config = decode_json( Path::Tiny::path($config_file)->slurp_utf8 );
    my @modules_list = ();
    # main structure to render UI
    my %modules_status_info = ();
    # columns are automatically filled in by operated data set
    $modules_status_info{'columns'} = ();
    # we define just first one
    $modules_status_info{'columns'}{'module_name'} = 1;

    foreach my $repo_config ( @{ $config->{'repositories'} } ) {
        Pakket::Web::Repo->create($repo_config);
        # filling in modules list
        my @modules = @{Pakket::Web::Repo->get_repo($repo_config->{'type'}, $repo_config->{'backend'})->all_object_ids};
        # removing "perl/" prefix
        map {s/perl\///g;} @modules;
        my $meta = $repo_config->{'path'};
        my @meta_parts = split '/', $meta;
        if (scalar @meta_parts == 4) {
          $meta = 'perl '. $meta_parts[2] . '_' . $meta_parts[1];
        } else {
          $meta =~ s/\///g;
        }
        push (@modules_list, {
          modules => \@modules,
          meta => $meta,
        });
    }

    foreach my $module_group ( @modules_list ) {
        foreach my $module_name ( @{$module_group->{'modules'}} ) {
            my $key = $module_group->{'meta'};
            $modules_status_info{$module_name}{$key} = 1;
            # keeping track of all existing columns
            $modules_status_info{'columns'}{$key} = 1;
        }
    }

    get '/info' => sub {
        my @repositories =  map { { 'type' => $_->{'type'},
                                    'path' => $_->{'path'} } }
                                @{ $config->{'repositories'} };
        return encode_json({
                'version' => $Pakket::Web::App::VERSION,
                'repositories' => [@repositories],
                });
    };

    # status page
    get '/status' => sub {
        set content_type => 'text/html';
        my @table_head_order = ('module_name', 'source', 'spec');
        my @table_head_fields_dataset = keys %{$modules_status_info{'columns'}};
        # merging table_head_fields_dataset into table_head_order
        foreach my $field ( @table_head_fields_dataset ) {
          push (@table_head_order, $field) unless first { $_ eq $field } @table_head_order;
        }
        my $dirname = dirname(__FILE__);
        my $main_template = Path::Tiny::path($dirname.'/views/status.html')->slurp_utf8;
        my $rows_html = '';

        # resetting iterator
        # and case insensitive module names sorting
        my @status_info_keys = sort {uc($a) cmp uc($b)} keys %modules_status_info;
        foreach my $key ( @status_info_keys ) {
            $rows_html .= '<tr>';
            # filling in fields
            foreach my $cell_name ( @table_head_order ) {
                if ($cell_name eq 'module_name') {
                    $rows_html .= '<td class="name">' . $key  . '</td>';
                } else {
                    my $cell_val = defined $modules_status_info{$key}->{$cell_name} ? '+' : '-';
                    $rows_html .= '<td '. ($cell_val eq '-' ? 'class="missing"' : '') . '>' . $cell_val  . '</td>';
                }
            }
            $rows_html .= '</tr>';
        }

        # porting table head array to template
        my @table_head_fields = @table_head_order;
        map {s/(.+)/<td>$1<\/td>/;} @table_head_fields;
        my $table_head_tmpl = '<tr>' . join('', @table_head_fields) . '</tr>';
        $main_template =~ s/\{TABLE_HEAD\}/$table_head_tmpl/;
        $main_template =~ s/\{TABLE_ROWS\}/$rows_html/g;
        return $main_template;
    };

}

1;

__END__

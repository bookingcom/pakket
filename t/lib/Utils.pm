package t::lib::Utils; ## no critic [NamingConventions::Capitalization]

use v5.22;
use warnings;
use namespace::clean -except => [qw(import)];

# core
use English '-no_match_vars';
use List::Util qw(all any);
use System::Command;

# non core
use Data::Dumper qw(Dumper);
use Encode;
use File::Copy::Recursive qw(dircopy);
use Log::Any::Adapter;
use Log::Dispatch;
use Module::Faker;
use Path::Tiny;
use Test2::V0;

# core (need to be after Test2)
use experimental qw(declared_refs refaliasing signatures);

# local
use Pakket::Log;
use Pakket::Repository::Backend::File;
use Pakket::Utils qw(encode_json_pretty);

# exports
use Exporter qw(import);
our @EXPORT_OK = qw(
    dont_match_any_item
    match_all_items
    match_any_item
    match_several_items
    test_prepare_context
    test_prepare_context_corpus
    test_prepare_context_real
    test_run
    test_web_prepare_context
);

Log::Any::Adapter->set(
    'Dispatch',
    'dispatcher' => arg_default_logger(),
);

sub arg_default_logger {
    return $_[1] || Log::Dispatch->new(
        'outputs' => [[
                'Screen',
                'min_level' => 'info',
                'newline'   => 1,
            ],
        ],
    );
}

sub generate_modules {
    my $fake_dist_dir = Path::Tiny->tempdir();

    Module::Faker->make_fakes({
            'source' => path(qw(t corpus fake_perl_mods)),
            'dest'   => $fake_dist_dir,
        },
    );

    return $fake_dist_dir;
}

sub config_web ($dirs) {
    return +{
        'allow_write'      => 1,
        'default_category' => 'perl',
        'log_file'         => $dirs->{'parcel'}->sibling('pakket-web.log'),
        'repositories'     => [{
                'backend' => {
                    'directory'      => $dirs->{'parcel'},
                    'file_extension' => 'tgz',
                    'type'           => 'file',
                },
                'path' => '/co7/5.28.1/parcel',
                'type' => 'parcel',
            },
            {
                'backend' => {
                    'directory'      => $dirs->{'snapshot'},
                    'file_extension' => '',
                    'type'           => 'file',
                    'validate_id'    => 0,
                },
                'path' => '/snapshot',
                'type' => 'snapshot',
            },
            {
                'backend' => {
                    'directory'      => $dirs->{'source'},
                    'file_extension' => 'tgz',
                    'type'           => 'file',
                },
                'path' => '/source',
                'type' => 'source',
            },
            {
                'backend' => "file://$dirs->{spec}?file_extension=json",
                'path'    => '/spec',
                'type'    => 'spec',
            },
        ],
    };
}

sub config (@dirs) {
    return +{
        'repositories' => {
            'spec'   => "file://$dirs[0]?file_extension=json",
            'source' => "file://$dirs[1]?file_extension=tgz",
            'parcel' => "file://$dirs[2]?file_extension=tgz",
        },
    };
}

sub test_prepare_context () {
    my $dir  = Path::Tiny->tempdir('pakket-test-repos-XXXXX', 'CLEANUP' => !$ENV{'DEBUG'});
    my @dirs = map {my $ret = $dir->child($_); $ret->mkpath; $ret} qw(spec source parcel install);

    return +(
        'repositories' => {
            'spec'   => "file://$dirs[0]?file_extension=json",
            'source' => "file://$dirs[1]?file_extension=tgz",
            'parcel' => "file://$dirs[2]?file_extension=tgz",
        },
        'install_dir' => "file://$dirs[3]",
        'dirs'        => \@dirs,
        'app_dir'     => path($ENV{'PWD'}),
        'app_run'     => [$EXECUTABLE_NAME, "-I$ENV{'PWD'}/lib", "$ENV{'PWD'}/bin/pakket"],
    );
}

sub test_prepare_context_corpus ($root) {
    my $temp = Path::Tiny->tempdir('pakket-test-repos-XXXXX', 'CLEANUP' => !$ENV{'DEBUG'});
    my @dirs = map {my $ret = $temp->child($_); $ret->mkpath; $ret} qw(spec source parcel install);
    foreach my $dir (qw(spec source parcel)) {
        dircopy("$ENV{'PWD'}/$root/$dir", $temp->child($dir));
    }

    my $config_path = $temp->child('pakket.json');
    my %result      = +(
        'repositories' => {
            'spec' => [
                'file',
                'directory'      => $dirs[0]->stringify,
                'file_extension' => '.json',
            ],
            'source' => [
                'file',
                'directory'      => $dirs[1]->stringify,
                'file_extension' => '.tgz',
            ],
            'parcel' => [
                'file',
                'directory'      => $dirs[2]->stringify,
                'file_extension' => 'tgz',                                     # test extension without dot
            ],
        },
        'default_category' => 'perl',
        'install_dir'      => $dirs[3]->stringify,
        'log_file'         => $temp->child('pakket.log')->stringify,
        'app_dir'          => $ENV{'PWD'},
        'app_config'       => $config_path->stringify,
        'app_run'          => [
            $EXECUTABLE_NAME,
            "-I$ENV{'PWD'}/lib",
            "$ENV{'PWD'}/bin/pakket",
        ],
    );
    my $config = encode_json_pretty(\%result);
    $ENV{'DEBUG'}
        and diag($config);

    $config_path->spew_utf8($config);
    $result{'test_root'} = $temp;
    $result{'test_dirs'} = \@dirs;

    $ENV{'DEBUG'}
        and diag(Encode::decode('UTF-8', `tree $root`, Encode::FB_CROAK));

    return %result;
}

sub test_prepare_context_real () {
    return test_prepare_context_corpus('t/corpus/repos.v3');
}

sub test_run ($args, $opt = {}, $wanted_exit_code = 0) {
    my $cmd = System::Command->new($args->@*, $opt,);

    my $cmdline = join (' ', $cmd->cmdline);
    note 'Running ', $cmdline;

    my @output;
    $cmd->loop_on(
        'stdout' => sub {chomp (my $line = shift); push @output, $line},
        'stderr' => sub {chomp (my $line = shift); push @output, $line},
    );

    my $exit_code = $cmd->close->exit;
    if ($exit_code != 0 && $wanted_exit_code == -1) {
        pass "The command '$cmdline' exited with code '$exit_code', which is non-0 like we wanted";
    } elsif ($exit_code != $wanted_exit_code) {
        fail(map {"$_\n"} "The command '$cmdline' exited with '$exit_code', but we wanted '$wanted_exit_code': $!",
            @output);
    } else {
        pass "The command '$cmdline' exited with code '$exit_code' like we wanted";
        if ($ENV{'DEBUG'}) {
            note "The output was:\n" . Dumper(@output);
        }
    }
    return $exit_code, \@output;
}

sub match_all_items ($string, @regexes) {
    all {$string =~ m/$_/m} @regexes
        or ok(0, "one of items didn't match: @regexes");
    return;
}

sub dont_match_any_item ($array, $match, $name = '', @rest) {
    my $is_matched = !!(any {m/$match/} $array->@*);
    ok(!$is_matched, $name || $match, (Dumper($array)) x !$is_matched, @rest);
    return;
}

sub match_any_item ($array, $match, $name = '', @rest) {
    my $is_matched = !!(any {m/$match/} $array->@*);
    ok($is_matched, $name || $match, (Dumper($array)) x !$is_matched, @rest);
    return;
}

sub match_several_items ($array, @match) {
    foreach my $line (@match) {
        match_any_item($array, "$line", "Should be in output: $line");
    }
    return;
}

sub test_web_prepare_context () {
    my @dirs = qw(spec source parcel snapshot);
    my $root = Path::Tiny->tempdir('pakket-test-web-XXXXX', 'CLEANUP' => !$ENV{'DEBUG'})->absolute;
    my %dirs = map {my $p = $root->child($_); $p->mkpath; $_ => $p} @dirs;
    dircopy("$ENV{'PWD'}/t/corpus/repos.v3/$_", $root->child($_)) foreach @dirs;

    my \%config = config_web(\%dirs);
    my $config_file = $root->child('pakket-web.json');

    $config_file->spew(encode_json_pretty(\%config));

    $ENV{'PAKKET_WEB_CONFIG'} = $config_file->stringify; ## no critic [Variables::RequireLocalizedPunctuationVars]

    $ENV{'DEBUG'}
        and diag(Encode::decode('UTF-8', `tree $root`, Encode::FB_CROAK));

    my %ctx = (
        %config,
        'test_root' => $root,                                                  # don't clean up test root while context is kept
    );

    return \%ctx;
}

1;

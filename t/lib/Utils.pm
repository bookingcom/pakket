package t::lib::Utils; ## no critic [NamingConventions::Capitalization]

use v5.22;
use strict;
use warnings;

# core
use English '-no_match_vars';
use List::Util qw(any);
use System::Command;

# non core
use Data::Dump qw(dd dump);
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
use namespace::clean;
use Exporter qw(import);
our @EXPORT_OK = qw(
    match_any_item
    match_several_items
    test_prepare_context
    test_prepare_context_real
    test_run
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

sub config (@dirs) {
    return +{
        'repositories' => {
            'spec'   => "file://$dirs[0]",
            'source' => "file://$dirs[1]",
            'parcel' => "file://$dirs[2]",
        },
    };
}

sub test_prepare_context () {
    my $dir  = Path::Tiny->tempdir('pakket-test-repos-XXXXX', 'CLEANUP' => !$ENV{'DEBUG'});
    my @dirs = map {my $ret = $dir->child($_); $ret->mkpath; $ret} qw(spec source parcel install);

    return +(
        'repositories' => {
            'spec'   => "file://$dirs[0]",
            'source' => "file://$dirs[1]",
            'parcel' => "file://$dirs[2]",
        },
        'install_dir' => "file://$dirs[3]",
        'dirs'        => \@dirs,
        'app_dir'     => path($ENV{'PWD'}),
        'app_run'     => [$EXECUTABLE_NAME, "-I$ENV{'PWD'}/lib", "$ENV{'PWD'}/bin/pakket"],
    );
}

sub test_prepare_context_real () {
    my $temp = Path::Tiny->tempdir('pakket-test-repos-XXXXX', 'CLEANUP' => !$ENV{'DEBUG'});
    my @dirs = map {my $ret = $temp->child($_); $ret->mkpath; $ret} qw(spec source parcel install);
    foreach my $dir (qw(spec source parcel)) {
        dircopy("$ENV{'PWD'}/t/corpus/repos.v3/$dir", $temp->child($dir));
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
        and diag(`tree $temp`);

    return %result;
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
            note "The output was:\n" . dump (@output);
        }
    }
    return $exit_code, \@output;
}

sub match_any_item ($array, $match, $name = '', @rest) {
    my $is_matched = !!(any {m/$match/} $array->@*);
    ok($is_matched, $name || $match, (dump $array) x !$is_matched, @rest);
    return;
}

sub match_several_items ($array, @match) {
    foreach my $line (@match) {
        match_any_item($array, "$line", "Should be in output: $line");
    }
    return;
}

1;

package Pakket::Utils;

# ABSTRACT: Utilities for Pakket

use v5.22;
use strict;
use warnings;

# core
use Carp;
use List::Util qw(any);
use experimental qw(declared_refs refaliasing signatures);
use version;

# non core
use File::ShareDir qw(dist_dir);
use JSON::MaybeXS;
use Path::Tiny;

# exports
use namespace::clean;
use Exporter qw(import);
our @EXPORT_OK = qw(
    clean_hash
    encode_json_canonical
    encode_json_one_line
    encode_json_pretty
    env_vars
    env_vars_build
    env_vars_passthrough
    expand_variables
    get_application_version
    is_writeable
    normalize_version

    difference
    difference_symmetric
    intersection
    union

    group_by

    flatten

    print_env

    shared_dir
);

sub get_application_version {
    return ($Pakket::Utils::VERSION && $Pakket::Utils::VERSION->{'original'}) // '3.1415';
}

sub normalize_version ($input) {
    my $version = version->parse($input);
    $version->is_qv
        and return $version->normal;
    return $version->stringify;
}

sub is_writeable ($path) {
    while (!$path->is_rootdir) {
        $path->exists
            and return -w $path;
        $path = $path->parent;
    }
    return -w $path;
}

## no critic [Subroutines::ProhibitManyArgs]

sub env_vars ($build_dir, $environment, %params) {
    my @params   = @params{qw(bootstrap_dir pkg_dir prefix use_prefix)};
    my $c_path   = generate_cpath(@params);
    my $lib_path = generate_lib_path(@params);
    my %c_opts   = (
        ('CPATH' => $c_path) x !!$c_path,
        'PKG_CONFIG_PATH' => generate_pkgconfig_path(@params),
        'LD_LIBRARY_PATH' => $lib_path,                                        # dynamic loader searches here at runtime
        'LIBRARY_PATH'    => $lib_path,                                        # linker searches here after -L

        # DO NOT set LD_RUN_PATH onto temp dirs - they will be baked into binary's rpath
        'LD_RUN_PATH' => $params{'prefix'}->child(qw(lib))->absolute->stringify,
    );

    # add path to libperl.so of current perl to LIBRARY_PATH
    chomp (my $archlib = `perl -MConfig -e 'print \$Config{archlib}'`);
    $c_opts{'LIBRARY_PATH'} = join (':', $c_opts{'LIBRARY_PATH'}, $archlib . '/CORE');

    my @perl5lib = (
        $params{'pkg_dir'}->child(qw(lib perl5))->absolute->stringify,
        ($params{'prefix'}->child(qw(lib perl5))->absolute->stringify) x !!$params{'use_prefix'},
        $params{'sources'}->child(qw(lib))->absolute->stringify,
        $params{'sources'}->child(qw(blib lib))->absolute->stringify,
        $params{'sources'}->child(qw(blib))->absolute->stringify,
        $params{'bootstrap_dir'}->child(qw(lib perl5))->absolute->stringify,

        # this make some tests fail, so doing this only for restricted amount of distributions
        ($params{'sources'}->absolute->stringify) x !!_expect_inc_dot($params{'sources'}),
    );
    my %perl_opts = (
        'PERL5LIB'                  => join (':', @perl5lib),
        'PERL_LOCAL_LIB_ROOT'       => $params{'pkg_dir'}->child(qw(lib perl5))->absolute->stringify,
        'PERL5_CPAN_IS_RUNNING'     => 1,
        'PERL5_CPANM_IS_RUNNING'    => 1,
        'PERL5_CPANPLUS_IS_RUNNING' => 1,
        'PERL_MM_USE_DEFAULT'       => 1,
        'PERL_MB_OPT'               => '--install_base ' . $params{'prefix'}->absolute->stringify,
        'PERL_MM_OPT'               => 'INSTALL_BASE=' . $params{'prefix'}->absolute->stringify,

        # By default ExtUtils::Install checks if a file wasn't changed then skip it which breaks
        # CanBundle::snapshot_build_dir(). To change that behaviour and force installer to copy all files,
        # ExtUtils::Install uses a parameter 'always_copy' or environment variable EU_INSTALL_ALWAYS_COPY.
        'EU_INSTALL_ALWAYS_COPY' => 1,
    );

    my %result = (
        'PATH' => generate_bin_path(@params, $params{'sources'}),
        %c_opts,
        %perl_opts,
        env_vars_passthrough(),
        env_vars_build($build_dir, %params),
    );

    my %env_meta = %{$environment // {}};
    @env_meta{keys %env_meta} = expand_variables_inplace([@env_meta{keys %env_meta}], \%result)->@*;

    return (%result, %env_meta);
}

sub _expect_inc_dot ($sources) {
    return any {$sources->child($_)->exists} qw(
        inc parts private builder lib/Devel/Symdump.pm constants.pl.PL openssl_config.PL pam.cfg.in
        File-NFSLock.spec.PL MyInstall.pm mkheader tab/misc.pl Configure.pm
    );
}

sub env_vars_build ($build_dir, %params) {
    return (
        'PACKAGE_BUILD_DIR' => $build_dir->absolute->stringify,
        'PACKAGE_PKG_DIR'   => $params{'pkg_dir'}->absolute->stringify,
        'PACKAGE_PREFIX'    => $params{'prefix'}->absolute->stringify,
        'PACKAGE_SOURCES'   => $params{'sources'}->absolute->stringify,
        'PACKAGE_SRC_DIR'   => $params{'sources'}->absolute->stringify,        # backward compatibility
    );
}

sub env_vars_passthrough {
    my %result = (
        'LANG'   => 'en_US.utf8',
        'LC_ALL' => 'en_US.utf8',
        %ENV{qw(HOME TERM TZ all_proxy http_proxy HTTP_PROXY https_proxy HTTPS_PROXY no_proxy NO_PROXY)},
    );
    return clean_hash(\%result)->%*;
}

sub generate_cpath ($bootstrap_dir, $pkg_dir, $prefix, $use_prefix) {
    my @incpaths = (                                                           # no tidy
        $pkg_dir->child('include'),
        ($prefix->child('include')) x !!$use_prefix,
        $bootstrap_dir->child('include'),
    );

    my @paths;
    foreach my $path (@incpaths) {
        $path->is_dir
            or next;
        push (@paths, map {$_->absolute->stringify} grep {$_->is_dir} $path, $path->children);
    }
    return join (':', @paths);
}

sub generate_bin_path ($bootstrap_dir, $pkg_dir, $prefix, $use_prefix, $sources) {
    my @paths = map {$_->absolute->stringify} $pkg_dir->child('bin'), ($prefix->child('bin')) x !!$use_prefix,
        $sources->child(qw(blib bin)), $bootstrap_dir->child('bin');
    $ENV{'PATH'}
        and push (@paths, $ENV{'PATH'});
    return join (':', @paths);
}

sub generate_lib_path ($bootstrap_dir, $pkg_dir, $prefix, $use_prefix) {
    my @paths = map {$_->absolute->stringify} $pkg_dir->child('lib'), ($prefix->child('lib')) x !!$use_prefix,
        $bootstrap_dir->child('lib');
    $ENV{'LD_LIBRARY_PATH'}
        and push (@paths, $ENV{'LD_LIBRARY_PATH'});
    return join (':', @paths);
}

sub generate_pkgconfig_path ($bootstrap_dir, $pkg_dir, $prefix, $use_prefix) {
    my @paths = map {$_->absolute->stringify} $pkg_dir->child(qw(lib pkgconfig)),
        ($prefix->child(qw(lib pkgconfig))) x !!$use_prefix, $bootstrap_dir->child(qw(lib pkgconfig));
    $ENV{'PKG_CONFIG_PATH'}
        and push (@paths, $ENV{'PKG_CONFIG_PATH'});
    return join (':', @paths);
}

sub encode_json_canonical ($content) {
    return JSON::MaybeXS->new->canonical->encode($content);
}

sub encode_json_pretty ($content) {
    return JSON::MaybeXS->new->convert_blessed->canonical->pretty->encode($content);
}

sub encode_json_one_line ($content) {
    return JSON::MaybeXS->new->convert_blessed->indent(0)->encode($content);
}

sub clean_hash ($data) {
    ref $data eq 'HASH'
        or return $data;
    foreach my $key (keys $data->%*) {
        $data->{$key} = clean_hash($data->{$key});
        if (!defined $data->{$key} || (ref $data->{$key} eq 'HASH' && !$data->{$key}->%*)) {
            delete $data->{$key};
            next;
        }
    }
    $data->%*
        and return $data;
    return {};
}

sub expand_variables ($variables_aref, $env_href) {
    $variables_aref
        or return [];

    my @copy = $variables_aref->@*;
    expand_variables_inplace(\@copy, $env_href);

    return \@copy;
}

sub expand_variables_inplace ($variables_aref, $env_href) {
    for my $var ($variables_aref->@*) {
        if (ref $var eq 'ARRAY') {
            __SUB__->($var, $env_href);
            next;
        }
        for my $key (keys $env_href->%*) {
            my $placeholder = '%' . uc ($key) . '%';
            $var =~ s{$placeholder}{$env_href->{$key}}msg;
        }
    }
    return $variables_aref;
}

sub union : prototype($$) { ## no critic (Subroutines::RequireArgUnpacking)
    my %union;
    $union{$_} = undef foreach ($_[0]->@*, $_[1]->@*);
    return keys %union;
}

sub intersection : prototype($$) { ## no critic (Subroutines::RequireArgUnpacking)
    my %left;
    $left{$_} = undef foreach $_[0]->@*;
    return grep {exists $left{$_}} $_[1]->@*;
}

sub difference : prototype($$) { ## no critic (Subroutines::RequireArgUnpacking)
    my %left;
    $left{$_} = undef foreach $_[0]->@*;
    delete @left{$_[1]->@*};
    return keys %left;
}

sub difference_symmetric : prototype($$) { ## no critic (Subroutines::RequireArgUnpacking)
    my (%left, %right);
    $left{$_}++ foreach $_[0]->@*;
    delete $left{$_} // $right{$_}++ foreach $_[1]->@*;

    return +(keys %left, keys %right);
}

sub group_by ($key_extractor, @values) {
    my %result;
    foreach (@values) {
        push ($result{$key_extractor->($_)}->@*, $_);
    }
    return \%result;
}

sub flatten {
    return map {ref $_ eq 'ARRAY' ? flatten($_->@*) : $_} @_;
}

sub print_env ($log) {
    $log->debug($_, '=', $ENV{$_}) foreach sort keys %ENV;
    return;
}

sub shared_dir ($child) {
    my $result;

    eval {
        my $dir = path(dist_dir('Pakket'), $child);
        if ($dir->exists) {
            $result = $dir->realpath;
        }

        1;
    } or do {
        chomp (my $error = $@ || 'zombie error');

        foreach my $dir (map {+(path($_, qw(auto share dist Pakket), $child), path($_, qw(.. share), $child))} @INC) {
            $dir->exists
                or next;

            $result = $dir->realpath;
            last;
        }

        $result
            or carp($error);
    };

    return $result;
}

1;

__END__

package Pakket::Utils;

# ABSTRACT: Utilities for Pakket

use v5.22;
use strict;
use warnings;

# core
use List::Util qw(any);
use experimental qw(declared_refs refaliasing signatures);
use version 0.77;

# non core
use JSON::MaybeXS;

# exports
use namespace::clean;
use Exporter qw(import);
our @EXPORT_OK = qw(
    clean_hash
    encode_json_canonical
    encode_json_pretty
    env_vars
    env_vars_build
    env_vars_passthrough
    env_vars_scaffold
    expand_variables
    is_writeable
    normalize_version
    get_application_version
);

sub get_application_version {
    return ($Pakket::Utils::VERSION && $Pakket::Utils::VERSION->{'original'}) // '3.1415';

    #state $name = __PACKAGE__ . '::VERSION';
    #return *{$name} // '3.1415';
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

    return (
        'PATH' => generate_bin_path(@params, $params{'sources'}),
        %c_opts,
        %perl_opts,
        env_vars_passthrough(),
        env_vars_build($build_dir, %params),
        %{$environment // {}},
    );
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

sub env_vars_scaffold ($params) {
    return (
        'PACKAGE_SOURCES' => $params->{'sources'}->absolute->stringify,
        'PACKAGE_SRC_DIR' => $params->{'sources'}->absolute->stringify,        # backward compatibility
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

sub generate_lib_path ($bootstrap_dir, $pkg_dir, $prefix, $use_prefix) {
    my @paths = map {$_->absolute->stringify} $pkg_dir->child('lib'), ($prefix->child('lib')) x !!$use_prefix,
        $bootstrap_dir->child('lib');
    $ENV{'LD_LIBRARY_PATH'}
        and push (@paths, $ENV{'LD_LIBRARY_PATH'});
    return join (':', @paths);
}

sub generate_bin_path ($bootstrap_dir, $pkg_dir, $prefix, $use_prefix, $sources) {
    my @paths = map {$_->absolute->stringify} $pkg_dir->child('bin'), ($prefix->child('bin')) x !!$use_prefix,
        $sources->child(qw(blib bin)), $bootstrap_dir->child('bin');
    $ENV{'PATH'}
        and push (@paths, $ENV{'PATH'});
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
    return JSON::MaybeXS->new->pretty->canonical->encode($content);
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

sub expand_variables ($variables, $env) {
    $variables
        or return [];

    my @copy = $variables->@*;
    _expand_flags_inplace(\@copy, $env);

    return \@copy;
}

sub _expand_flags_inplace ($variables, $env) {
    for my $var ($variables->@*) {
        if (ref $var eq 'ARRAY') {
            _expand_flags_inplace($var, $env);
            next;
        }
        for my $key (keys $env->%*) {
            my $placeholder = '%' . uc ($key) . '%';
            $var =~ s{$placeholder}{$env->{$key}}msg;
        }
    }
    return;
}

1;

__END__

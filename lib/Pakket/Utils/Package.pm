package Pakket::Utils::Package; ## no critic [Subroutines::ProhibitExportingUndeclaredSubs]

# ABSTRACT: Package utility functions

use v5.22;
use strict;
use warnings;

# core
use Carp;
use English qw(-no_match_vars);
use experimental qw(declared_refs refaliasing signatures);

# non core
use Log::Any qw($log);

# exports
use namespace::clean;
use Exporter qw(import);
our @EXPORT_OK = qw(
    PAKKET_PACKAGE_STR
    canonical_name
    parse_requirement
    short_name
    short_variant
    validate_name
);

use constant { ## no critic [RegularExpressions::ProhibitComplexRegexes]
    'PAKKET_PACKAGE_STR' => qr{
        \A
        \s*
        (?:
            (?<category> [^\/]+)\/
        )?
        (?:
            (?<name> [^=]+)
        )
        (?:=
            (?<version>[^:]+)
            (?::
                (?<release>.*)
            )?
        )?
        \s*
        \z
    }xms,
    'REQ_STR_REGEX' => qr{
        \A \s*
        (>=|<=|==|!=|[<>])? \s*
        (\S*) \s*
        \z
    }xms,
};

sub canonical_name ($category, $name, $version = undef, $release = undef) {
    $version && $release
        and return sprintf '%s/%s=%s:%s', $category, $name, $version, $release;

    $version
        and return sprintf '%s/%s=%s', $category, $name, $version;

    return short_name($category, $name);
}

sub parse_requirement ($requirement, $default = '==') {
    $requirement
        or return +('>=', '0');

    if ($requirement =~ REQ_STR_REGEX()) {
        return +($1 // $default, $2);
    }

    croak($log->critical('Cannot parse requirement:', $requirement));
}

sub short_name ($category, $name) {
    return join ('/', $category, $name);
}

sub short_variant ($version, $release) {
    $version && $release
        and return sprintf '%s:%s', $version, $release;

    $version
        and return $version;

    return '0';
}

sub validate_name ($name) {
    if ($name =~ m{/}xms) {

        # $name =~ s{::}{-}gr;
        croak($log->critical('Invalid package name:', $name));
    }

    return;
}

1;

__END__

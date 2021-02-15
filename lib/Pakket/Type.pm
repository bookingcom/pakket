# vim: foldmethod=marker
package Pakket::Type;

# ABSTRACT: Type definitions for Pakket

use v5.22;
use strict;
use warnings;
use namespace::autoclean;

# core
use Carp;

# non core
use Log::Any qw($log);
use Module::Runtime qw(require_module);
use Moose::Util::TypeConstraints;
use Ref::Util qw(is_ref is_arrayref is_hashref);
use Safe::Isa;

# local
use Pakket::Constants qw(
    PAKKET_VALID_PHASES
    PAKKET_VALID_PREREQ_TYPES
);

use experimental qw(declared_refs refaliasing signatures);

# => enums ------------------------------------------------------------------------------------------------------- {{{1

enum 'PakketPhase'      => [keys PAKKET_VALID_PHASES()->%*];
enum 'PakketPrereqType' => [keys PAKKET_VALID_PREREQ_TYPES()->%*];

# => PakketDownloadStrategy -------------------------------------------------------------------------------------- {{{1

subtype 'PakketDownloadStrategy', as 'Object', where {
    $_->$_does('Pakket::Role::CanDownload')
}, message {
    'Must be a Pakket::Role::CanDownload'
};

coerce 'PakketDownloadStrategy', from 'Object', via {return $_};

# => PakketRepositoryBackend ------------------------------------------------------------------------------------- {{{1

subtype 'PakketRepositoryBackend', as 'Object', where {
    $_->$_does('Pakket::Role::Repository::Backend')
        || is_hashref($_)
        || is_arrayref($_)
        || (!is_ref($_) && length)
}, message {
    'Must be a Pakket::Repository::Backend object or a URI string or arrayref'
};

coerce 'PakketRepositoryBackend', from 'Str', via {return _coerce_backend_from_str($_)};

coerce 'PakketRepositoryBackend', from 'ArrayRef', via {return _coerce_backend_from_arrayref($_)};

coerce 'PakketRepositoryBackend', from 'HashRef', via {return _coerce_backend_from_hashref($_)};

sub _coerce_backend_from_str {
    my ($uri) = @_;

    my ($scheme) = $uri =~ m{^ ( \w+ ) :// }xms;
    $scheme = ucfirst lc $scheme;
    $scheme = 'Http' if ($scheme eq 'Https');

    my $class = "Pakket::Repository::Backend::$scheme";
    eval {require_module($class); 1;} or do {
        croak($log->critical("Failed to load backend '$class': $@"));
    };

    return $class->new_from_uri($uri);
}

sub _coerce_backend_from_arrayref ($arrayref) {
    my ($scheme, $data) = @{$arrayref};

    $scheme = ucfirst lc $scheme;
    $scheme = 'Http' if $scheme eq 'Https';                                    # backend is called Http for both
    $data //= {};

    is_hashref($data) or do {                                                  # For backward compatibility with old config.
        my (undef, @params) = @{$arrayref};
        $data = {@params};
    };

    is_hashref($data)
        or croak($log->critical('Second arg to backend is not hash'));

    _show_repo_banner(delete $data->{'banner'});

    my $class = "Pakket::Repository::Backend::$scheme";
    eval {require_module($class); 1;} or do {
        croak($log->critical("Failed to load backend '$class': $@"));
    };

    return $class->new($data);
}

sub _coerce_backend_from_hashref ($hash_ref) {
    _show_repo_banner(delete $hash_ref->{'banner'});

    my %hash_copy = $hash_ref->%*;
    my $type      = delete $hash_copy{'type'};
    $type = ucfirst lc $type;
    my $class = "Pakket::Repository::Backend::$type";
    eval {
        require_module($class);
        1;
    } or do {
        croak($log->critical("Failed to load backend '$class': $@"));
    };

    return $class->new(\%hash_copy);
}

sub _show_repo_banner ($banner) {
    $banner
        or return;

    $log->warn($_) foreach split (m/\n/, $banner);

    return;
}

# => PakketHelperVersioner --------------------------------------------------------------------------------------- {{{1

subtype 'PakketHelperVersioner', as 'Object', where {$_->$_does('Pakket::Role::Versioner')};

coerce 'PakketHelperVersioner', from 'Str', via {
    my $type  = $_;
    my $class = "Pakket::Helper::Versioner::$type";

    eval {
        require_module($class);
        1;
    } or do {
        my $error = $@ || 'Zombie error';
        croak($log->critical("Could not load versioning module ($type)"));
    };

    return $class->new();
};

1;

__END__

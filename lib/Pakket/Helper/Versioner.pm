package Pakket::Helper::Versioner;

# ABSTRACT: A versioner class

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

# core
use Carp;
use experimental qw(declared_refs refaliasing signatures);

# non core
use Module::Runtime qw(require_module);

# local
use Pakket::Type;

has 'type' => (
    'is'       => 'ro',
    'isa'      => 'PakketHelperVersioner',
    'coerce'   => 1,
    'required' => 1,
    'handles'  => ['compare', 'compare_version', 'compare_full'],
);

with qw(
    Pakket::Role::HasLog
);

use constant {
    'COND_REGEX' => qr/^ \s* (>=|<=|==|!=|[<>]) \s* (\S*) \s* $/xms,
};

sub BUILDARGS ($class, %args) {
    return Pakket::Role::HasLog->BUILDARGS(%args); ## no critic [Modules::RequireExplicitInclusion]
}

# A filter string is a comma-separated list of conditions
# A condition is of the form "OP VER"
# OP is >=, <=, !=, ==, >, <
# VER is a version string valid for the version module
# Whitespace is ignored
sub parse_req_string ($self, $req_string) {
    my @conditions = split /,/xms, $req_string;
    my @filters;
    foreach my $condition (@conditions) {
        if ($condition !~ COND_REGEX()) {
            $condition = ">= $condition";
        }

        my @filter = $condition =~ COND_REGEX();
        push @filters, \@filter;
    }

    return \@filters;
}

my %op_map = (
    '>=' => sub {$_[0] >= 0},
    '<=' => sub {$_[0] <= 0},
    '==' => sub {$_[0] == 0},
    '!=' => sub {$_[0] != 0},
    '>'  => sub {$_[0] > 0},
    '<'  => sub {$_[0] < 0},
);

sub filter_version ($self, $req_string, $versions) {
    foreach my $filter (@{$self->parse_req_string($req_string)}) {
        my ($op, $req_version) = @{$filter};

        @{$versions} = grep +($op_map{$op}->($self->compare($_, $req_version))), @{$versions};
    }

    return;
}

sub select_versions ($self, $conditions, $versions) {
    my @versions = $versions->@*;
    foreach my $filter ($conditions->@*) {
        my ($op, $req_version) = $filter->@*;
        @versions = grep +($op_map{$op}->($self->compare($_, $req_version))), @versions;
    }

    return @versions;
}

# Filter all @versions based on $req_string
sub latest ($self, $category, $name, $req_string, @versions) {
    $self->filter_version($req_string, \@versions);

    @versions
        or croak($self->log->criticalf('No versions provided for %s/%s', $category, $name));

    # latest_version
    my $latest;
    foreach my $version (@versions) {
        if (!defined $latest) {
            $latest = $version;
            next;
        }

        if ($self->compare($latest, $version) < 0) {
            $latest = $version;
        }
    }

    return $latest;
}

sub select_latest ($self, $versions) {
    my @sorted = sort {$self->compare($a, $b)} $versions->@*;
    return $sorted[-1];
}

sub is_satisfying ($self, $req_string, @versions) {
    $self->filter_version($req_string, \@versions);

    return !!(@versions > 0);
}

__PACKAGE__->meta->make_immutable;

1;

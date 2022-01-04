package Pakket::Web::Controller::Repos;

# ABSTRACT: A web repos controller

use v5.28;
use namespace::autoclean;
use Mojo::Base 'Mojolicious::Controller', -signatures, -async_await;
use experimental qw(declared_refs refaliasing signatures);

use List::Util qw(uniq);

use Module::Runtime qw(use_module);

use Pakket::Utils qw(get_application_version flatten);

has 'cpan' => sub ($self) {return use_module('Pakket::Helper::Cpan')->new};

## no critic [Modules::RequireEndWithOne, Lax::RequireEndWithTrueConst]

async sub get_index ($self) {
    my \%repos = $self->stash('repos');

    my @repos    = flatten(values %repos);
    my @cache    = map           {$_->all_objects_cache} @repos;
    my @packages = uniq sort map {keys $_->%*} @cache;

    my @result = map {+{$_->%{qw(type path)}}} @repos;
    return $self->render(
        'json' => {
            'repositories' => \@result,
            'packages'     => \@packages,
            'version'      => get_application_version(),
        },
    );
}

async sub get_updates ($self) {
    my \%repos = $self->stash('repos');

    my @result;
    if (exists $repos{'spec'}) {
        my $repo      = $repos{'spec'}[0];
        my \%cache    = $repo->all_objects_cache;
        my \%outdated = $self->cpan->outdated(\%cache);
        @result = map {"$_=$outdated{$_}{'cpan_version'}"} sort keys %outdated;
    }

    return $self->render(
        'json' => {
            'items'   => \@result,
            'version' => get_application_version(),
        },
    );
}

async sub info ($self) {
    my \%repos_by_name = $self->stash('repos');
    my @repos          = grep {$_->type ne 'snapshot'} flatten(values %repos_by_name);
    @repos = map {{'type' => $_->type, 'path' => $_->path}} @repos;

    my %result = (
        'repositories' => \@repos,
        'version'      => get_application_version(),
    );

    return $self->respond_to(
        'json' => {'json' => \%result},
        'yaml' => {'yaml' => \%result},
        'any'  => {'json' => \%result},

        #         'any'  => {
        #             'text'   => 'Unsupported Content-Type',
        #             'status' => 415,
        #         },
    );
}

## no critic [ControlStructures::ProhibitDeepNests]
async sub all_packages ($self) {
    my \%repos_by_name = $self->stash('repos');
    my @repos = grep {$_->type ne 'snapshot'} flatten(values %repos_by_name);

    my %all_packages;
    for my $repo (@repos) {
        next if $repo->type eq 'snapshot';
        my \@object_ids = $repo->all_object_ids;
        foreach my $id (@object_ids) {
            $all_packages{$id}{$repo->path} = 1;
        }
    }

    my %result;
    foreach my $repo (@repos) {
        next if $repo->type eq 'snapshot';
        my $type = $repo->type;
        my $path = $repo->path;
        my ($p1, $p2, $p3) = split (m{/}, $repo->path);

        if ($type eq 'spec') {                                                 # here detect outdated packages
            my \%cache              = $repo->all_objects_cache;
            my \%outdated           = $self->cpan->outdated(\%cache);
            my \%cpan_distributions = $self->cpan->latest_distributions;

            foreach my $short_name (keys %cache) {
                my \%versions = $cache{$short_name};
                foreach my $version (keys %versions) {
                    my \%releases = $versions{$version};
                    foreach my $release (keys %releases) {
                        my $id = "$short_name=$version:$release";
                        exists $cpan_distributions{$short_name}
                            and $result{$id}{'cpan'} = 1;
                        exists $outdated{$short_name}
                            and $result{$id}{'cpan_version'} = $outdated{$short_name}{'cpan_version'};
                    }
                }
            }
        }

        if ($type eq 'spec' or $type eq 'source') {
            foreach my $id (keys %all_packages) {
                $result{$id}{$type} = $all_packages{$id}{$path} // 0;
            }
        } else {
            foreach my $id (keys %all_packages) {
                $result{$id}{$p3}{$p2} = $all_packages{$id}{$path} // 0;
            }
        }
    }

    return $self->render('json', \%result);
}

1;

__END__

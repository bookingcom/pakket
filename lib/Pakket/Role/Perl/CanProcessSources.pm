package Pakket::Role::Perl::CanProcessSources;

# ABSTRACT: A role providing ability to process raw sources with dzil or MakeMaker

use v5.22;
use Moose::Role;
use namespace::autoclean;

# core
use List::Util   qw(any);
use experimental qw(declared_refs refaliasing signatures);

# non core
use Path::Tiny;

# local
use Pakket::Helper::Download;

with qw(
    Pakket::Role::RunCommand
);

sub process_dist_ini ($self, $query, $opts, $params) {
    any {$params->{'sources'}->child($_)->exists} qw(META.json META.yml)
        and return;

    any {$params->{'sources'}->child($_)->exists} qw(dist.ini)
        or return;

    $self->log->info(q{Processing sources with 'dzil build'});
    my $dir = Path::Tiny->tempdir(
        'TEMPLATE' => 'pakket-dzil-' . $query->name . '-XXXXXXXXXX',
        'CLEANUP'  => 1,
    );

    $self->run_command_sequence(
        $params->{'sources'},
        {'env' => _get_env($opts)},
        [qw(dzil authordeps --missing)],
        [qw(dzil build --no-tgz), "--in=$dir"],
    ) or $self->croak('Unable to process sources with dzil');

    return $params->{'sources'} = $dir;
}

sub process_makefile_pl ($self, $package, $opts, $params) {
    any {$params->{'sources'}->child($_)->exists} qw(META.json META.yml)
        and return;

    any {$params->{'sources'}->child($_)->exists} qw(Makefile.PL)
        or return;

    $self->log->info(q{Processing sources with 'make dist'});
    $self->run_command_sequence(
        $params->{'sources'}, {'env' => _get_env($opts)},
        [qw(perl -f Makefile.PL)], [qw(make dist DISTVNAME=pakket_new_dist)],
    ) or $self->croak('Unable to process sources with MakeMaker');

    my $download = Pakket::Helper::Download->new(
        'name' => $package->name,
        'url'  => sprintf ('file://%s/pakket_new_dist.tar.gz', $params->{'sources'}->absolute),
        $self->%{qw(log log_depth)},
    );
    return $params->{'sources'} = $download->to_dir;
}

sub _get_env ($opts) {
    return {
        %{$opts->{'env'} // {}},
        'PATH'     => $ENV{'PATH_ORIG'}     // $ENV{'PATH'}     // '',
        'PERL5LIB' => $ENV{'PERL5LIB_ORIG'} // $ENV{'PERL5LIB'} // '',
    };
}

1;

__END__

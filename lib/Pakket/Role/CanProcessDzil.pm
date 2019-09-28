package Pakket::Role::CanProcessDzil;
# ABSTRACT: A role providing ability to process raw sourcess with dzil

use v5.22;
use Moose::Role;
use File::chdir;
use Path::Tiny   qw< path >;
use Log::Any     qw< $log >;

sub process_dist_ini {
    my ($self, $package, $sources) = @_;

    return $sources if $sources->child('META.json')->exists || $sources->child('META.yml')->exists;
    return $sources unless $sources->child('dist.ini')->exists;

    $log->debugf("Processing sources with 'dzil build'");
    my $dir = Path::Tiny->tempdir( 'CLEANUP' => 1 );
    {
        local $CWD = $sources->absolute;
        my $path =$ENV{PATH_ORIG} // $ENV{PATH} // '';
        my $lib  =$ENV{PERL5LIB_ORIG} // $ENV{PERL5LIB} // '';
        my $cmd = "PATH=$path PERL5LIB=$lib dzil build --no-tgz --in=$dir";
        my $ecode = system($cmd);
        Carp::croak("Unable to run '$cmd'") if $ecode;
    }
    return $dir;
}

no Moose::Role;

1;

__END__

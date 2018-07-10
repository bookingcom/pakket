package Pakket::Role::CanProcessDzil;
# ABSTRACT: A role providing ability to process raw sourcess with dzil

use Moose::Role;
use File::chdir;
use Path::Tiny   qw< path >;
use Log::Any     qw< $log >;

sub process_dist_ini {
    my ($self, $package, $sources) = @_;

    return $sources if $sources->child('META.json')->exists;
    return $sources unless $sources->child('dist.ini')->exists;

    my $dir = Path::Tiny->tempdir( 'CLEANUP' => 1 );
    {
        local $CWD = $sources->absolute;
        my $lib =$ENV{PERL5LIB_ORIG} // '';
        my $cmd = "PERL5LIB=$lib dzil build --no-tgz --in=$dir";
        my $ecode = system($cmd);
        Carp::croak("Unable to run '$cmd'") if $ecode;
    }
    return $dir;
}

no Moose::Role;

1;

__END__

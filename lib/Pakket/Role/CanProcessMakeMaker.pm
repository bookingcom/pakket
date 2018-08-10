package Pakket::Role::CanProcessMakeMaker;
# ABSTRACT: A role providing ability to process raw sourcess with MakeMaker

use Moose::Role;
use File::chdir;
use Path::Tiny   qw< path >;
use Log::Any     qw< $log >;

use Pakket::Downloader::ByUrl;

sub process_makefile_pl {
    my ($self, $package, $sources) = @_;

    return $sources if $sources->child('META.json')->exists || $sources->child('META.yml')->exists;
    return $sources unless $sources->child('Makefile.PL')->exists;

    $log->debugf("Processing sources with 'make dist'");
    {
        local $CWD = $sources->absolute;
        my $path =$ENV{PATH_ORIG} // $ENV{PATH} // '';
        my $lib  =$ENV{PERL5LIB_ORIG} // $ENV{PERL5LIB} // '';
        $self->_exec("PATH=$path PERL5LIB=$lib perl -f Makefile.PL");
        $self->_exec("PATH=$path PERL5LIB=$lib make dist DISTVNAME=new_dist");
        my $download = Pakket::Downloader::ByUrl::create($package->name, 'file://new_dist.tar.gz');
        return $download->to_dir;
    }
}

sub _exec {
    my ($self, $cmd) = @_;
    my $ecode = system($cmd);
    Carp::croak("Unable to run '$cmd'") if $ecode;
}

no Moose::Role;

1;

__END__

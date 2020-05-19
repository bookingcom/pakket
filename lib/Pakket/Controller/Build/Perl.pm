package Pakket::Controller::Build::Perl;

# ABSTRACT: Build Perl Pakket packages

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

# core
use List::Util qw(any);
use experimental qw(declared_refs refaliasing signatures);

# non core
use Path::Tiny;

# local
use Pakket::Type::PackageQuery;
use Pakket::Utils qw(
    env_vars
    expand_variables
);

has 'exclude_packages' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'default' => sub {
        {
            'perl'     => 1,
            'perl_mlb' => 1,                                                   # MetaCPAN bug
        };
    },
);

has 'type' => (
    'is'      => 'ro',
    'isa'     => 'Str',
    'default' => 'perl',
);

with qw(
    Pakket::Role::Builder
    Pakket::Role::Perl::BootstrapModules
    Pakket::Role::Perl::HasCpan
);

sub execute ($self, %params) {
    my %env = env_vars(
        $params{'build_dir'},
        $params{'metadata'}{'environment'},
        'bootstrap_dir' => $self->bootstrap_dir,
        %params,
    );

    $params{'opts'}              = {'env' => \%env};
    $params{'configure-options'} = expand_variables($params{'metadata'}{'configure-options'}, \%env);
    $params{'make-options'}      = expand_variables($params{'metadata'}{'make-options'}, \%env);
    $params{'pre'}               = expand_variables($params{'metadata'}{'pre'}, \%env);
    $params{'post'}              = expand_variables($params{'metadata'}{'post'}, \%env);

    local %ENV = %env;                                                         # keep all env changes locally
    $self->print_env();

    if ($params{'pre'}) {
        $self->run_command_sequence(@params{qw(sources opts)}, $params{'pre'}->@*)
            or $self->croak('Failed to run pre-build commands for', $params{'name'});
    }

    # taken from cpanminus
    my %must_use_mm
        = map {($_ => 1)} qw(version ExtUtils-MakeMaker ExtUtils-ParseXS ExtUtils-Install ExtUtils-Manifest);

    # If you have a Build.PL file but we can't load Module::Build, it means you didn't declare it as a dependency
    # If you have a Makefile.PL, we can at least use that, otherwise, we'll croak
    my $has_build_pl    = $params{'sources'}->child('Build.PL')->exists;
    my $has_makefile_pl = $params{'sources'}->child('Makefile.PL')->exists;

    my @sequence;
    if ($has_build_pl && !exists $must_use_mm{$params{'name'}}) {
        my $has_module_build = any {                                           # Do we have Module::Build?
            $self->run_command(@params{qw(sources opts)}, ['perl', $_, '-e1'])
        }
        qw(-MModule::Build -MModule::Build::Tiny);

        if ($has_module_build) {
            @sequence = $self->_build_pl_cmds(%params);
        } else {
            $self->log->warn(q{Defined Build.PL but can't load Module::Build. Will try Makefile.PL});
        }
    }

    if ($has_makefile_pl && !@sequence) {
        @sequence = $self->_makefile_pl_cmds(%params);
    }

    @sequence
        or $self->croak('Could not find an installer (Makefile.PL/Build.PL)');

    $self->run_command_sequence(@params{qw(sources opts)}, @sequence)
        or $self->croak('Failed to run build commands for', $params{'name'});

    if ($params{'post'}) {
        $self->run_command_sequence(@params{qw(sources opts)}, $params{'post'}->@*)
            or $self->croak('Failed to run post-build commands for', $params{'name'});
    }

    return;
}

sub _build_pl_cmds ($self, %params) {
    return (
        ['perl', '-V'],                                                        # info
        ['perl', '-f', 'Build.PL', $params{'configure-options'}->@*],          # configure
        ['perl', '-f', './Build', $params{'make-options'}->@*],                # build
        (['perl', '-f', './Build', 'test']) x !!($params{'no-test'} < 1),      # test TODO support run test ignore failure
        ['perl', '-f', './Build', 'install', '--destdir', $params{'build_dir'}->absolute->stringify],    # install
        (['rm', '-rf', $params{'pkg_dir'}->child('man')->absolute->stringify]) x !!$params{'no-man'}, # cleanup man pages
    );
}

sub _makefile_pl_cmds ($self, %params) {
    return (
        ['perl', '-V'],                                                        # info
        ['perl', '-f', 'Makefile.PL', 'verbose', 'NO_PACKLIST=1', 'NO_PERLLOCAL=1', $params{'configure-options'}->@*], # configure
        ['make', $params{'make-options'}->@*],                                 # build
        (['make', 'test'],) x !!($params{'no-test'} < 1),                      # test
        ['make', 'install', 'DESTDIR=' . $params{'build_dir'}->absolute->stringify],    # install
        (['rm', '-rf', $params{'pkg_dir'}->child('man')->absolute->stringify]) x !!$params{'no-man'}, # cleanup man pages
    );
}

sub bootstrap_prepare_modules ($self) {
    my @modules      = $self->bootstrap_modules->@*;
    my %requirements = map {                                                   # no tidy
        my $q = Pakket::Type::PackageQuery->new_from_string(
            $_,
            'default_category' => 'perl',
            'as_prereq'        => 0,
        );
        +($q->short_name, $q)
    } @modules;

    return +(\@modules, \%requirements);
}

sub bootstrap ($self, $controller, $modules, $requirements) {
    $requirements->%*
        or return;

    my @phases    = qw(configure build runtime test);
    my @types     = qw(requires);
    my $build_dir = Path::Tiny->tempdir(sprintf ($controller->BUILD_DIR_TEMPLATE(), 'bootstrap-prepare'),
        'CLEANUP' => !$controller->keep);
    my $bootstrap_builder = $controller->clone(
        'installer'   => undef,
        'no_continue' => 1,
        'no_test'     => 2,
        'dry_run'     => 1,
    );
    {                                                                          # Pass I: bootstrap toolchain - build without dependencies
        $self->log->notice('Pass I: bootstrap perl builder - build without dependencies');
        $bootstrap_builder->_process_queries(
            [$requirements->@{$modules->@*}],
            'no_prereqs' => 1,
            'build_dir'  => $build_dir,
        );
    }
    {                                                                          # Pass II: bootstrap toolchain - build dependencies only
        $self->log->notice('Pass II: bootstrap perl builder - build dependencies only');
        $bootstrap_builder->_process_queries(
            [$requirements->@{$modules->@*}],
            'phases'       => [@phases],
            'types'        => [@types],
            'build_dir'    => $build_dir,
            'processing'   => {},
            'prereqs_only' => 1,
        );
    }
    {                                                                          # Pass III: bootstrap toolchain - rebuild with dependencies
        $self->log->notice('Pass III: bootstrap perl builder - rebuild with dependencies');
        $bootstrap_builder->clone(
            'no_test' => $self->config->{'perl'}{'build'}{'no-test'} // 0,
            'dry_run' => 0,
        )->_process_queries(
            [$requirements->@{$modules->@*}],
            'phases'     => [@phases],
            'types'      => [@types],
            'build_dir'  => $build_dir,
            'processing' => {},
            'overwrite'  => 2,
        );
    }

    return;
}

before [qw(execute)] => sub ($self, @) {
    return $self->log_depth_change(+1);
};

after [qw(execute)] => sub ($self, @) {
    return $self->log_depth_change(-1);
};

__PACKAGE__->meta->make_immutable;

1;

__END__

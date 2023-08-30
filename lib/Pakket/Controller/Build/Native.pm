package Pakket::Controller::Build::Native;

# ABSTRACT: Build pative pakket packages

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

# local
use Pakket::Utils qw(
    env_vars
    expand_variables
    print_env
);

# core
use experimental qw(declared_refs refaliasing signatures);

has 'exclude_packages' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'default' => sub {+{}},
);

has 'type' => (
    'is'      => 'ro',
    'isa'     => 'Str',
    'default' => 'native',
);

with qw(
    Pakket::Role::Builder
);

sub execute ($self, %params) {
    my %env = (
        env_vars(
            $params{'build_dir'},
            $params{'metadata'}{'environment'},
            'bootstrap_dir' => $self->bootstrap_dir,
            %params,
            ),

        # 'PREFIX' => $params{'prefix'}->absolute,
    );

    $params{'opts'}              = {'env' => \%env};
    $params{'configure-options'} = expand_variables($params{'metadata'}{'configure-options'}, \%env);
    $params{'make-options'}      = expand_variables($params{'metadata'}{'make-options'},      \%env);
    $params{'pre'}               = expand_variables($params{'metadata'}{'pre'},               \%env);
    $params{'post'}              = expand_variables($params{'metadata'}{'post'},              \%env);

    local %ENV = %env;                                                         # keep all env changes locally
    print_env($self->log);

    ## no critic  [ErrorHandling::RequireCarping]
    if ($params{'pre'}) {
        $self->run_command_sequence($params{'sources'}, $params{'opts'}, $params{'pre'}->@*)
            or die sprintf ("Failed to run pre-build commands for %s\n", $params{'id'});
    }

    my @run_params         = ($params{'sources'}, $params{'opts'});
    my @configurator_flags = ('--prefix=' . $params{'prefix'}->absolute);
    my @make_flags;

    my $configurator;
    if ($params{'sources'}->child('configure')->is_file) {
        $configurator = './configure';
    } elsif ($params{'sources'}->child('config')->is_file) {
        $configurator = './config';
    } elsif ($params{'sources'}->child('Configure')->is_file) {
        $configurator = './Configure';
    } elsif ($params{'sources'}->child('CMakeLists.txt')->is_file) {
        $configurator = 'cmake';
        my $out_tree_build = $params{'sources'}->child('pakket-cmake-build');
        if ($out_tree_build->exists) {
            @run_params         = ($params{'sources'}, {$params{'opts'}->%*, 'cwd' => $out_tree_build->absolute});
            @configurator_flags = ('-DCMAKE_INSTALL_PREFIX=' . $params{'prefix'}->absolute, '..');
        } else {
            @configurator_flags = ('-DCMAKE_INSTALL_PREFIX=' . $params{'prefix'}->absolute, '.');
        }
    } elsif ($params{'sources'}->child('Makefile')->is_file) {
        $self->log->warn('Only Makefile is found, trying to run it');
        undef @configurator_flags;
        push (@make_flags, 'PREFIX=' . $params{'prefix'}->absolute);
    } else {
        die sprintf ("Cannot find configurator '[Cc]onfigure', 'config' or cmake for: %s\n", $params{'id'});
    }

    my @commands = (                                                           # no tidy
        ([                                                                  # configure
                $configurator,                    @{$self->config->{'native'}{'build'}{'configure-options'} // []},
                $params{'configure-options'}->@*, @configurator_flags,
            ]
        ) x !!@configurator_flags,
        ([                                                                  # make
                'make', @{$self->config->{'native'}{'build'}{'make-options'} // []}, $params{'make-options'}->@*,
                @make_flags,
            ]
        ) x !!!$params{'metadata'}{'no-make'},
        (                                                                      # test
            ['make', 'test']
        ) x !!($params{'no-test'} < 1),
        ([                                                                  # install
                'make', $params{'metadata'}{'install-command'} // 'install', "DESTDIR=$params{build_dir}", @make_flags,
            ]
        ) x !!!$params{'metadata'}{'no-install'},
        (                                                                      # cleanup man pages
            ['rm', '-rf', $params{'pkg_dir'}->child('man')->absolute->stringify]
        ) x !!$params{'no-man'},
    );

    $self->run_command_sequence(@run_params, @commands)
        or die sprintf ("Failed to run build commands for package: %s\n", $params{'id'});

    if ($params{'post'}) {
        $self->run_command_sequence($params{'sources'}, $params{'opts'}, $params{'post'}->@*)
            or die sprintf ("Failed to run post-build commands for %s\n", $params{'id'});
    }

    return;
}

sub bootstrap_prepare_modules ($self) {
    return +([], {});
}

sub bootstrap ($self, $scaffolder, $modules, $requirements) {
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

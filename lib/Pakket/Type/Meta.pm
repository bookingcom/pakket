package Pakket::Type::Meta;

# ABSTRACT: An object representing a pakket Metadata

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use MooseX::Clone;
use namespace::autoclean;

# core
use Carp;
use List::Util qw(any none);
use experimental qw(declared_refs refaliasing signatures);

# non core
use YAML ();

# local
use Pakket::Utils::Package qw(
    parse_package_id
);
use Pakket::Utils qw(clean_hash get_application_version);

has [qw(prereqs scaffold build test)] => (
    'is'  => 'ro',
    'isa' => 'Maybe[HashRef]',
);

has [qw(path)] => (
    'is'  => 'ro',
    'isa' => 'Maybe[Path::Tiny]',
);

with qw(
    MooseX::Clone
);

sub BUILD ($self, @) {
    return;
}

sub as_hash ($self) {
    my $result = {
        $self->%{qw(prereqs scaffold build test)},
        'version' => get_application_version(),
    };
    return clean_hash($result);
}

sub new_from_prereqs ($class, $input, %additional) {
    return $class->new(
        'prereqs' => $input,
        %additional,
    );
}

sub new_from_metafile ($class, $path, %additional) {
    my $input = YAML::Load($path->slurp_utf8);
    return $class->new_from_metadata($input, %additional, 'path' => $path->absolute);
}

sub new_from_metadata ($class, $input, %additional) {
    my $params = _try_meta_v3($input) // _try_meta_v2($input);
    delete $params->{'version'};
    return $class->new($params->%*, %additional);

    #ref $meta{'source'} eq 'ARRAY'
    #and $meta{'source'} = join ('', $meta{'source'}->@*);
}

sub new_from_specdata ($class, $input, %additional) {
    my $params      = clean_hash(_try_spec_v3($input) // _try_spec_v2($input) // _try_spec_metafile($input) // {});
    my %params_copy = $params->%*;
    delete $params_copy{'version'};
    return $class->new(%params_copy, %additional);
}

# private

sub _try_spec_v3 ($spec) {
    exists $spec->{'Pakket'} && $spec->{'Pakket'}{'version'} && $spec->{'Pakket'}{'version'} >= 3
        and return $spec->{'Pakket'};
    return;
}

sub _try_spec_v2 ($spec) {
    if (exists $spec->{'Prereqs'} || exists $spec->{'build_opts'}) {
        my %build;
        if (my $build_opts = $spec->{'build_opts'}) {
            $build{'environment'}       = $build_opts->{'env_vars'};
            $build{'configure-options'} = $build_opts->{'configure_flags'};
            $build{'make-options'}      = $build_opts->{'build_flags'};
            my @pre = (
                $build_opts->{'pre-build'} ? $build_opts->{'pre-build'}->@* : (),
                $build_opts->{'pre_build'} ? $build_opts->{'pre_build'}->@* : (),
            );
            my @post = (
                $build_opts->{'post-build'} ? $build_opts->{'post-build'}->@* : (),
                $build_opts->{'post_build'} ? $build_opts->{'post_build'}->@* : (),
            );
            @pre
                and $build{'pre'} = \@pre;
            @post
                and $build{'post'} = \@post;
            $build{'no-test'} = $spec->{'skip'}{'test'};
        }
        return {
            'prereqs' => _convert_spec_v2_prereqs($spec->{'Prereqs'}) || {},
            'build'   => \%build,
        };
    }
    return;
}

sub _try_spec_metafile ($spec) {
    exists $spec->{'Meta'}
        and return $spec->{'Meta'}->%*;
    return;
}

sub _convert_spec_v2_prereqs ($prereqs) {
    $prereqs
        or return {};

    my \%prereqs = $prereqs;

    my %result;
    foreach my $category (keys %prereqs) {
        foreach my $phase (keys $prereqs{$category}->%*) {
            foreach my $name (keys $prereqs{$category}{$phase}->%*) {
                $result{$phase}{'requires'}{"$category/$name"} = $prereqs{$category}{$phase}{$name}{'version'};
            }
        }
    }
    return \%result;
}

sub _try_meta_v3 ($data) {
    exists $data->{'Pakket'}
        and return $data->{'Pakket'};

    return;
}

sub _try_meta_v2 ($meta) {
    return clean_hash({
            'prereqs'  => _convert_meta_v2_prereqs($meta),
            'scaffold' => _convert_meta_v2_scaffold($meta),
            'build'    => _convert_meta_v2_build($meta),
        },
    );
}

sub _convert_meta_v2_prereqs ($meta) {
    my $requires = $meta->{'requires'};
    my %result;
    foreach my $type (keys $requires->%*) {
        foreach my $dep ($requires->{$type}->@*) {
            my ($c, $n, $v) = parse_package_id($dep);
            $c && $n
                or croak('Cannot parse requirement: ', $dep);
            $result{$type}{'requires'}{"$c/$n"} = $v // 0;
        }
    }
    return \%result;
}

sub _convert_meta_v2_scaffold ($meta) {
    my \%meta = $meta;
    my %skip = %{$meta{'skip'} // {}};
    delete @skip{qw(test)};
    my %result = (
        (%meta{'patch'}) x !!$meta{'patch'},
        ('environment' => $meta{'manage'}{'env'}) x !!$meta{'manage'}{'env'},
        ('pre'         => $meta{'pre-manage'}) x !!$meta{'pre-manage'},
        ('post'        => $meta{'post-manage'}) x !!$meta{'post-manage'},
        ('skip'        => \%skip) x !!%skip,
    );
    return \%result;
}

sub _convert_meta_v2_build ($meta) {
    my \%meta   = $meta;
    my $no_test = $meta{'skip'}{'test'};
    my %result  = (
        ('environment' => $meta{'build'}{'env'}) x !!$meta{'build'}{'env'},
        ('pre'               => $meta{'pre-build'}) x !!$meta{'pre-build'},
        ('post'              => $meta{'post-build'}) x !!$meta{'post-build'},
        ('configure-options' => $meta{'build'}{'configure-options'}) x !!$meta{'build'}{'configure-options'},
        ('make-options'      => $meta{'build'}{'make-options'}) x !!$meta{'build'}{'make-options'},
        ('no-test'           => $no_test) x !!defined $no_test,
    );
    return \%result;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

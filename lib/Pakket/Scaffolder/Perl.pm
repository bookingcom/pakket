package Pakket::Scaffolder::Perl;
# ABSTRACT: Scffolding Perl distributions

use Moose;

use version;
use Archive::Any;
use CPAN::Meta::Prereqs;
use JSON::MaybeXS qw< decode_json encode_json >;
use Module::CoreList;
use Path::Tiny qw< path >;
use Ref::Util qw< is_arrayref is_hashref >;
use TOML qw< to_toml >;
use Log::Any qw< $log >;

use Pakket::Utils qw< generate_json_conf >;
use Pakket::Scaffolder::Perl::Module;
use Pakket::Scaffolder::Perl::CPANfile;

with 'Pakket::Scaffolder::Role::Backend',
    'Pakket::Scaffolder::Role::Config',
    'Pakket::Scaffolder::Role::Terminal',
    'Pakket::Scaffolder::Perl::Role::Borked';

has metacpan_api => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    builder => '_build_metacpan_api',
);

has phases => (
    is      => 'ro',
    isa     => 'ArrayRef',
);

has processed_dists => (
    is      => 'ro',
    isa     => 'HashRef',
    default => sub { +{} },
);

has modules => (
    is      => 'ro',
    isa     => 'HashRef',
);

has prereqs => (
    is      => 'ro',
    isa     => 'CPAN::Meta::Prereqs',
    lazy    => 1,
    builder => '_build_prereqs',
);

sub _build_metacpan_api {
    my $self = shift;
    return (
        $ENV{'PAKKET_METACPAN_API'}
        || $self->pakket_config->{'perl'}{'metacpan_api'}
        || "https://fastapi.metacpan.org"
    );
}

sub _build_prereqs {
    my $self = shift;
    return CPAN::Meta::Prereqs->new( $self->modules );
}

sub BUILDARGS {
    my ( $class, @args ) = @_;
    my %args = @args == 1 ? %{ $args[0] } : @args;

    my $module   = delete $args{'module'};
    my $cpanfile = delete $args{'cpanfile'};
    die "provide either 'module' or 'cpanfile'\n"
        unless $module xor $cpanfile;

    $args{'modules'} = $module
        ? Pakket::Scaffolder::Perl::Module->new( name => $module, %args )->prereq_specs
        : Pakket::Scaffolder::Perl::CPANfile->new( cpanfile => $cpanfile )->prereq_specs;


    $args{'phases'} = [qw< configure runtime >];
    if ( exists $args{'additional_phases'} and is_arrayref( $args{'additional_phases'} ) ) {
        push @{ $args{'phases'} } =>
            grep { $_ eq 'develop' or $_ eq 'test' } @{ $args{'additional_phases'} };
    }

    return \%args;
}

sub run {
    my $self = shift;

    for my $phase ( @{ $self->phases } ) {
        $log->debugf( "phase: %s", $phase );
        for my $type (qw< requires recommends suggests >) {
            next unless is_hashref( $self->modules->{ $phase }{ $type } );

            my $requirements = $self->prereqs->requirements_for( $phase, $type );
            $self->create_config_for( module => $_, $requirements )
                for sort keys %{ $self->modules->{ $phase }{ $type } };
        }
    }

    if ( $self->json_file ) {
        generate_json_conf( $self->json_file, $self->config_dir );
    }
}

sub create_config_for {
    my ( $self, $type, $name, $requirements ) = @_;

    return if exists $self->known_names_to_skip->{ $name };
    return if Module::CoreList::is_core($name) and !${Module::CoreList::upstream}{$name};
    return if $self->processed_dists->{ $name }++;

    my $release = $self->get_release_info($type, $name, $requirements);
    return if exists $release->{'skip'};

    my $dist_name    = $release->{'distribution'};
    my $rel_version  = $release->{'version'};
    my $download_url = $self->rewrite_download_url( $release->{'download_url'} );
    $log->infof( "%s-> Working on %s (%s)", $self->spaces, $dist_name, $rel_version );
    $self->set_depth( $self->depth + 1 );

    my $conf_path = path( ( $self->config_dir // '.' ), 'perl', $dist_name );
    $conf_path->mkpath;

    my $conf_file = path( $conf_path, "$rel_version.toml" );

    # download source if dir provided and file doesn't already exist
    if ( $self->source_dir ) {
        if ( $download_url ) {
            my $source_file = path( $self->source_dir, ( $download_url =~ s{^.+/}{}r ) );
            if ( !$source_file->exists ) {
                $source_file->parent->mkpath;
                $self->ua->mirror( $download_url, $source_file );
            }
            if ( $self->extract ) {
                my $archive = Archive::Any->new( $source_file );
                $archive->extract( $self->source_dir );
                $source_file->remove;
            }
        }
        else {
            $log->errorf( "--- can't find download_url for %s-%s", $dist_name, $rel_version );
        }
    }

    if ( $conf_file->exists ) {
        $self->set_depth( $self->depth - 1 );
        return;
    }

    my $package = {
        Package => {
            category => 'perl',
            name     => $dist_name,
            version  => $rel_version,
        },
    };

    my $dep_modules = $release->{'prereqs'};
    my $dep_prereqs = CPAN::Meta::Prereqs->new( $dep_modules );

    # options: configure, develop, runtime, test
    for my $phase ( @{ $self->phases } ) {
        my $prereq_data = $package->{'Prereqs'}{'perl'}{$phase} = +{};

        for my $dep_type (qw< requires recommends suggests >) {
            next unless is_hashref( $dep_modules->{ $phase }{ $dep_type } );

            my $dep_requirements = $dep_prereqs->requirements_for( $phase, $dep_type );

            for my $module ( keys %{ $dep_modules->{ $phase }{ $dep_type } } ) {
                next if exists $self->known_names_to_skip->{ $module }
                        or Module::CoreList::is_core($module) and !${Module::CoreList::upstream}{$name};

                my $rel = $self->get_release_info( module => $module, $dep_requirements );
                next if exists $rel->{'skip'};

                $prereq_data->{ $rel->{'distribution'} } = +{
                    version => ( $rel->{'write_version_as_zero'} ? "0" : $rel->{'version'} )
                };
            }

            # recurse through those as well
            $self->create_config_for( dist => $_, $dep_requirements )
                for keys %{ $package->{'Prereqs'}{'perl'}{$phase} };
        }
    }

    $self->set_depth( $self->depth - 1 );

    $conf_file->spew_utf8( to_toml($package) );
}

sub get_dist_name {
    my ( $self, $module_name ) = @_;
    $module_name = $self->known_incorrect_name_fixes->{ $module_name }
        if exists $self->known_incorrect_name_fixes->{ $module_name };

    my $dist_name;
    eval {
        my $response = $self->ua->get( $self->metacpan_api . "/module/$module_name" );
        die if $response->{'status'} != 200;
        my $content = decode_json $response->{'content'};
        $dist_name  = $content->{'distribution'};
        1;
    } or die "-> Cannot find module by name: '$module_name'\n";
    return $dist_name;
}

sub get_release_info {
    my ( $self, $type, $name, $requirements ) = @_;

    my $dist_name = $type eq 'module'
        ? $self->get_dist_name($name)
        : $name;

    return +{ skip => 1 }
        if exists $self->known_names_to_skip->{ $dist_name }
           or Module::CoreList::is_core($dist_name) and !${Module::CoreList::upstream}{$name};

    my $req_as_hash = $requirements->as_string_hash;
    my $write_version_as_zero = !!(
        defined $req_as_hash->{ $name }
        and version->parse( $req_as_hash->{ $name } =~ s/[^0-9.]//gr ) == 0
    );

    # first try the latest

    my $latest = $self->get_latest_release_info( $dist_name );
    $latest->{'write_version_as_zero'} = $write_version_as_zero;
    return $latest
        if defined $latest->{'version'}
           and defined $latest->{'download_url'}
           and $requirements->accepts_module( $name => $latest->{'version'} );

    # else: fetch all release versions for this distribution

    my $release_prereqs;
    my $version;
    my $download_url;

    my %all_dist_releases;
    {
        my $res = $self->ua->post( $self->metacpan_api . "/release",
                               +{ content => $self->get_release_query($dist_name) });
        die "can't find any release for $dist_name\n" if $res->{'status'} != 200;
        my $res_body = decode_json $res->{'content'};

        %all_dist_releases =
            map {
                $_->{'fields'}{'version'}[0] => {
                    prereqs      => $_->{'_source'}{'metadata'}{'prereqs'},
                    download_url => $_->{'_source'}{'download_url'},
                }
            }
            @{ $res_body->{'hits'}{'hits'} };
    }

    # get the matching version according to the spec

    for my $v ( sort { version->parse($b) <=> version->parse($a) } keys %all_dist_releases ) {
        if ( $requirements->accepts_module($name => $v) ) {
            $version         = $v;
            $release_prereqs = $all_dist_releases{$v}{prereqs} || {};
            $download_url    =
                $self->rewrite_download_url( $all_dist_releases{$v}{download_url} );
            last;
        }
    }
    $version or die "Cannot match release for $dist_name\n";

    $version = $self->known_incorrect_version_fixes->{ $dist_name }
        if exists $self->known_incorrect_version_fixes->{ $dist_name };

    return +{
        distribution          => $dist_name,
        version               => $version,
        prereqs               => $release_prereqs,
        download_url          => $download_url,
        write_version_as_zero => $write_version_as_zero,
    };
}

sub rewrite_download_url {
    my ( $self, $download_url ) = @_;
    my $rewrite = $self->pakket_config->{'perl'}{'metacpan'}{'rewrite_download_url'};
    return $download_url unless is_hashref($rewrite);
    my ( $from, $to ) = @{$rewrite}{qw< from to >};
    return ( $download_url =~ s/$from/$to/r );
}

sub get_latest_release_info {
    my ( $self, $dist_name ) = @_;

    my $res = $self->ua->get( $self->metacpan_api . "/release/$dist_name" );
    return unless $res->{'status'} == 200; # falling back to check all

    my $res_body= decode_json $res->{'content'};

    return +{
        distribution => $dist_name,
        version      => $res_body->{'version'},
        download_url => $res_body->{'download_url'},
        prereqs      => $res_body->{'metadata'}{'prereqs'},
    };
}

sub get_release_query {
    my ( $self, $dist_name ) = @_;

    return encode_json({
        query  => {
            bool => {
                must => [
                    { term  => { distribution => $dist_name } },
                    { terms => { status => [qw< cpan latest >] } }
                ]
            }
        },
        fields  => [qw< version >],
        _source => [qw< metadata.prereqs download_url >],
        size    => 999,
    });
}


__PACKAGE__->meta->make_immutable;
no Moose;
1;
__END__

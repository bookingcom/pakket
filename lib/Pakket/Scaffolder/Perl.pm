package Pakket::Scaffolder::Perl;
# ABSTRACT: Scffolding Perl distributions

use Moose;
use MooseX::StrictConstructor;
use version 0.77;
use Archive::Any;
use CPAN::Meta::Prereqs;
use JSON::MaybeXS     qw< decode_json encode_json >;
use Ref::Util         qw< is_arrayref is_hashref >;
use Path::Tiny        qw< path    >;
use TOML              qw< to_toml >;
use Log::Any          qw< $log    >;
use Carp ();

use Pakket::Utils       qw< generate_json_conf >;
use Pakket::Utils::Perl qw< should_skip_module >;
use Pakket::Scaffolder::Perl::Module;
use Pakket::Scaffolder::Perl::CPANfile;

with qw<
    Pakket::Scaffolder::Role::Backend
    Pakket::Scaffolder::Role::Config
    Pakket::Scaffolder::Role::Terminal
    Pakket::Scaffolder::Perl::Role::Borked
>;

use constant {
    'ARCHIVE_DIR_TEMPLATE' => 'ARCHIVE-XXXXXX',
};

has 'metacpan_api' => (
    'is'      => 'ro',
    'isa'     => 'Str',
    'lazy'    => 1,
    'builder' => '_build_metacpan_api',
);

has 'phases' => (
    'is'  => 'ro',
    'isa' => 'ArrayRef',
);

has 'processed_dists' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'default' => sub { return +{} },
);

has 'modules' => (
    'is'  => 'ro',
    'isa' => 'HashRef',
);

has 'prereqs' => (
    'is'      => 'ro',
    'isa'     => 'CPAN::Meta::Prereqs',
    'lazy'    => 1,
    'builder' => '_build_prereqs',
);

sub _build_metacpan_api {
    my $self = shift;
    return $ENV{'PAKKET_METACPAN_API'}
        || $self->pakket_config->{'perl'}{'metacpan_api'}
        || 'https://fastapi.metacpan.org';
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
    Carp::croak("Please provide either 'module' or 'cpanfile'")
        unless $module xor $cpanfile;

    if ( $module ) {
        my ( $version, $phase, $type ) = delete @args{qw< version phase type >};
        $args{'modules'} =
            Pakket::Scaffolder::Perl::Module->new(
                'name' => $module,
                ( version => $version )x!! defined $version,
                ( phase   => $phase   )x!! defined $phase,
                ( type    => $type    )x!! defined $type,
            )->prereq_specs;
    }
    else {
        $args{'modules'} =
            Pakket::Scaffolder::Perl::CPANfile->new(
                'cpanfile' => $cpanfile
            )->prereq_specs;
    }

    $args{'phases'} = [ qw< configure runtime > ];

    if ( exists $args{'additional_phases'} and is_arrayref( $args{'additional_phases'} ) ) {
        push @{ $args{'phases'} } =>
            grep { $_ eq 'develop' or $_ eq 'test' } @{ $args{'additional_phases'} };
    }

    return \%args;
}

sub run {
    my $self = shift;
    my %failed;

    for my $phase ( @{ $self->phases } ) {
        $log->debugf( 'phase: %s', $phase );
        for my $type ( qw< requires recommends suggests > ) {
            next unless is_hashref( $self->modules->{ $phase }{ $type } );

            my $requirements = $self->prereqs->requirements_for( $phase, $type );

            for ( sort keys %{ $self->modules->{ $phase }{ $type } } ) {
                eval {
                    $self->create_config_for( module => $_, $requirements );
                    1;
                } or do {
                    my $err = $@ || 'zombie error';
                    $failed{$_} = $err;
                };
            }
        }
    }

    if ( $self->json_file ) {
        generate_json_conf( $self->json_file, $self->config_dir );
    }

    for my $f ( keys %failed ) {
        $log->infof( "[FAILED] %s: %s", $f, $failed{$f} );
    }

    return;
}

sub skip_name {
    my ( $self, $name ) = @_;

    if ( should_skip_module($name) ) {
        $log->debugf( "%s* skipping %s (core module, not dual-life)", $self->spaces, $name );
        return 1;
    }

    if ( exists $self->known_names_to_skip->{ $name } ) {
        $log->debugf( "%s* skipping %s (known 'bad' name for configuration)", $self->spaces, $name );
        return 1;
    }

    return 0;
}

sub create_config_for {
    my ( $self, $type, $name, $requirements ) = @_;
    return if $self->skip_name($name);
    return if $self->processed_dists->{ $name }++;

    my $release = $self->get_release_info($type, $name, $requirements);
    return if exists $release->{'skip'};

    my $dist_name    = $release->{'distribution'};
    my $rel_version  = $release->{'version'};
    my $download_url = $self->rewrite_download_url( $release->{'download_url'} );
    $log->infof( '%s-> Working on %s (%s)', $self->spaces, $dist_name, $rel_version );
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
                $self->extract_archive( $dist_name, $rel_version, $source_file );
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
        'Package' => {
            'category' => 'perl',
            'name'     => $dist_name,
            'version'  => $rel_version,
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
                next if $self->skip_name($module);

                my $rel = $self->get_release_info( module => $module, $dep_requirements );
                next if exists $rel->{'skip'};

                $prereq_data->{ $rel->{'distribution'} } = +{
                    'version' => ( $rel->{'write_version_as_zero'} ? "0" : $rel->{'version'} )
                };
            }

            # recurse through those as well
            $self->create_config_for( 'dist' => $_, $dep_requirements )
                for keys %{ $package->{'Prereqs'}{'perl'}{$phase} };
        }
    }

    $self->set_depth( $self->depth - 1 );

    $conf_file->spew_utf8( to_toml($package) );
}

sub extract_archive {
    my ( $self, $dist_name, $rel_version, $source_file ) = @_;

    my $archive_path = Path::Tiny->tempdir(
        'TEMPLATE' => ARCHIVE_DIR_TEMPLATE(),
        'DIR'      => $self->source_dir,
        'CLEANUP'  => 1,
    );
    my $archive = Archive::Any->new( $source_file );
    $archive->extract( $archive_path );
    my @children = $archive_path->children();
    my $final_name = $dist_name . '-' . $rel_version;
    if (@children == 0) {
        $log->infof( 'Archive %s is empty, skipping', $source_file->stringify);
    }
    elsif (@children == 1 &&
           $children[0]->is_dir()) {
        my $child = $children[0];
        my $dir_name = $child->basename;
        $log->debugf( 'Archive %s contains single directory [%s], using as [%s]', $source_file->stringify, $dir_name, $final_name);
        my $target = path( $self->source_dir, $final_name);
        $child->move( $target );
    }
    else {
        $log->debugf( 'Archive %s contains multiple entries, will put inside directory called [%s]', $source_file->stringify, $final_name);
        my $target = path( $self->source_dir, $final_name);
        $archive_path->move( $target );
    }

    $source_file->remove;
}

sub get_dist_name {
    my ( $self, $module_name ) = @_;
    $module_name = $self->known_incorrect_name_fixes->{ $module_name }
        if exists $self->known_incorrect_name_fixes->{ $module_name };

    my $dist_name;
    eval {
        my $mod_url     = $self->metacpan_api . "/module/$module_name";
        my $release_url = $self->metacpan_api . "/release/$module_name";
        my $response    = $self->ua->get($mod_url);

        $response->{'status'} == 200
            or $response = $self->ua->get($release_url);

        $response->{'status'} != 200
            and Carp::croak("Cannot fetch $mod_url or $release_url");

        my $content = decode_json $response->{'content'};
        $dist_name  = $content->{'distribution'};
        1;
    } or do {
        my $error = $@ || 'Zombie error';
        $log->debug($error);
    };

    # another check (if not found yet): check if name matches a distribution name
    if ( !$dist_name ) {
        eval {
            my $name = $module_name =~ s/::/-/rgsmx;
            my $res = $self->ua->post( $self->metacpan_api . '/release',
                +{ 'content' => $self->get_is_dist_name_query($name) } );

            $res->{'status'} == 200 or Carp::croak();
            my $res_body = decode_json $res->{'content'};
            $res_body->{'hits'}{'total'} > 0 or Carp::croak();
            $dist_name = $name;
            1;
        } or do {
            my $error = $@ || 'Zombie error';
            Carp::croak("-> Cannot find module by name: '$module_name'");
        };
    }

    return $dist_name;
}

sub get_release_info {
    my ( $self, $type, $name, $requirements ) = @_;

    my $dist_name = $type eq 'module'
        ? $self->get_dist_name($name)
        : $name;

    return +{ 'skip' => 1 } if $self->skip_name($dist_name);

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
        Carp::croak("Can't find any release for $dist_name") if $res->{'status'} != 200;
        my $res_body = decode_json $res->{'content'};

        %all_dist_releases =
            map {
                $_->{'fields'}{'version'}[0] => {
                    'prereqs'      => $_->{'_source'}{'metadata'}{'prereqs'},
                    'download_url' => $_->{'_source'}{'download_url'},
                }
            }
            @{ $res_body->{'hits'}{'hits'} };
    }

    # get the matching version according to the spec

    my @valid_versions;
    for my $v ( keys %all_dist_releases ) {
        eval {
            version->parse($v);
            push @valid_versions => $v;
            1;
        } or do {
            my $err = $@ || 'zombie error';
            $log->debugf( '[VERSION ERROR] distribution: %s, version: %s, error: %s',
                          $dist_name, $v, $err );
        };
    }

    for my $v ( sort { version->parse($b) <=> version->parse($a) } @valid_versions ) {
        if ( $requirements->accepts_module($name => $v) ) {
            $version         = $v;
            $release_prereqs = $all_dist_releases{$v}{'prereqs'} || {};
            $download_url    =
                $self->rewrite_download_url( $all_dist_releases{$v}{'download_url'} );
            last;
        }
    }
    $version or Carp::croak("Cannot match release for $dist_name");

    $version = $self->known_incorrect_version_fixes->{ $dist_name }
        if exists $self->known_incorrect_version_fixes->{ $dist_name };

    return +{
        'distribution'          => $dist_name,
        'version'               => $version,
        'prereqs'               => $release_prereqs,
        'download_url'          => $download_url,
        'write_version_as_zero' => $write_version_as_zero,
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
        'distribution' => $dist_name,
        'version'      => $res_body->{'version'},
        'download_url' => $res_body->{'download_url'},
        'prereqs'      => $res_body->{'metadata'}{'prereqs'},
    };
}

sub get_is_dist_name_query {
    my ( $self, $name ) = @_;

    return encode_json(
        {
            'query'  => {
                'bool' => {
                    'must' => [
                        { 'term'  => { 'distribution' => $name } },
                    ]
                }
            },
            'fields' => [qw< distribution >],
            'size'   => 0,
        }
    );
}

sub get_release_query {
    my ( $self, $dist_name ) = @_;

    return encode_json(
        {
            'query'  => {
                'bool' => {
                    'must' => [
                        { 'term'  => { 'distribution' => $dist_name } },
                        # { 'terms' => { 'status' => [qw< cpan latest >] } }
                    ]
                }
            },
            'fields'  => [qw< version >],
            '_source' => [qw< metadata.prereqs download_url >],
            'size'    => 999,
        }
    );
}


__PACKAGE__->meta->make_immutable;
no Moose;
1;
__END__

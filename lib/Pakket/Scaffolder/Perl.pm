package Pakket::Scaffolder::Perl;
# ABSTRACT: Scffolding Perl distributions

use Moose;
use MooseX::StrictConstructor;
use version 0.77;
use Carp ();
use Archive::Any;
use CPAN::DistnameInfo;
use CPAN::Meta::Prereqs;
use JSON::MaybeXS       qw< decode_json encode_json >;
use Ref::Util           qw< is_arrayref is_hashref >;
use Path::Tiny          qw< path >;
use Types::Path::Tiny   qw< Path  >;
use Log::Any            qw< $log >;

use Pakket::Package;
use Pakket::Types;
use Pakket::Utils::Perl qw< should_skip_module >;
use Pakket::Scaffolder::Perl::Module;
use Pakket::Scaffolder::Perl::CPANfile;

with qw<
    Pakket::Role::HasConfig
    Pakket::Role::HasSpecRepo
    Pakket::Role::HasSourceRepo
    Pakket::Role::Perl::BootstrapModules
    Pakket::Scaffolder::Perl::Role::Borked
    Pakket::Scaffolder::Role::Backend
    Pakket::Scaffolder::Role::Terminal
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
    'is'       => 'ro',
    'isa'      => 'ArrayRef[PakketPhase]',
    'required' => 1,
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

has 'spec_index' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'lazy'    => 1,
    'builder' => '_build_spec_index',
);

has 'prereqs' => (
    'is'      => 'ro',
    'isa'     => 'CPAN::Meta::Prereqs',
    'lazy'    => 1,
    'builder' => '_build_prereqs',
);

has 'download_dir' => (
    'is'      => 'ro',
    'isa'     => Path,
    'lazy'    => 1,
    'builder' => '_build_download_dir',
);

has 'cache_dir' => (
    'is'        => 'ro',
    'isa'       => Path,
    'coerce'    => 1,
    'predicate' => '_has_cache_dir',
);

has 'file_02packages' => (
    'is'      => 'ro',
    'isa'     => 'Str',
);

has 'cpan_02packages' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'lazy'    => 1,
    'builder' => '_build_cpan_02packages',
);

sub _build_metacpan_api {
    my $self = shift;
    return $ENV{'PAKKET_METACPAN_API'}
        || $self->config->{'perl'}{'metacpan_api'}
        || 'https://fastapi.metacpan.org';
}

sub _build_prereqs {
    my $self = shift;
    return CPAN::Meta::Prereqs->new( $self->modules );
}

sub _build_download_dir {
    my $self = shift;
    return Path::Tiny->tempdir( 'CLEANUP' => 1 );
}

sub _build_spec_index {
    my $self = shift;
    my $spec_index = $self->spec_repo->all_object_ids;
    my %spec_index;
    for ( @{ $spec_index } ) {
        m{^.*?/(.*)=(.*?)$};
        $spec_index{$1}{$2} = 1;
    }
    return \%spec_index;
}

sub _build_cpan_02packages {
    my $self = shift;
    my $ret  = +{};
    my ( $dir, $file );

    if ( $self->file_02packages ) {
        $file = path( $self->file_02packages );
        $log->infof( "Using 02packages file: %s", $self->file_02packages );

    } else {
        $dir  = Path::Tiny->tempdir;
        $file = path( $dir, '02packages.details.txt' );
        $log->infof( "Downloading 02packages" );
        $self->ua->mirror( 'https://cpan.metacpan.org/modules/02packages.details.txt', $file );
    }

    chomp( my @content = $file->lines_utf8 );
    shift @content for 0..8; # remove headers

    for my $c ( @content ) {
        my ( $name, $latest, $path ) =
            $c =~ /^([^\s]+)\s+([^\s]+)\s+([^\s]+)\s*$/;

        my $d = CPAN::DistnameInfo->new($path);

        $ret->{$name} = {
            'distribution'   => $d->dist,
            'latest_version' => $d->version,
        };
    }

    return $ret;
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

    return \%args;
}

sub run {
    my $self = shift;
    my %failed;

    # Bootstrap toolchain
    for my $dist ( @{ $self->perl_bootstrap_modules } ) {
        # TODO: check versions
        if ( exists $self->spec_index->{$dist} ) {
            $log->debugf( 'Skipping %s (already have version: %s)',
                          $dist, $self->spec_index->{$dist} );
            next;
        }

        $log->debugf( 'Bootstrapping config: %s', $dist );
        my $requirements = $self->prereqs->requirements_for(qw< configure requires >);
        eval {
            $self->create_spec_for( dist => $dist, $requirements );
            1;
        } or do {
            my $err = $@ || 'zombie error';
            Carp::croak("Cannot bootstrap toolchain distribution: $dist ($err)\n");
        };
    }

    # the rest
    for my $phase ( @{ $self->phases } ) {
        $log->debugf( 'Phase: %s', $phase );
        for my $type ( qw< requires recommends suggests > ) {
            next unless is_hashref( $self->modules->{ $phase }{ $type } );

            my $requirements = $self->prereqs->requirements_for( $phase, $type );

            for my $module ( sort keys %{ $self->modules->{ $phase }{ $type } } ) {
                eval {
                    $self->create_spec_for( module => $module, $requirements );
                    1;
                } or do {
                    my $err = $@ || 'zombie error';
                    $failed{$module} = $err;
                };
            }
        }
    }

    for my $f ( keys %failed ) {
        $log->infof( "[FAILED] %s: %s", $f, $failed{$f} );
    }

    $log->info( 'Done' );
}

sub skip_name {
    my ( $self, $name ) = @_;

    if ( should_skip_module($name) ) {
        $log->debugf( "%sSkipping %s (core module, not dual-life)", $self->spaces, $name );
        return 1;
    }

    if ( exists $self->known_names_to_skip->{ $name } ) {
        $log->debugf( "%sSkipping %s (known 'bad' name for configuration)", $self->spaces, $name );
        return 1;
    }

    return 0;
}

sub unpack {
    my ( $self, $target, $file ) = @_;

    my $archive = Archive::Any->new($file);

    if ( $archive->is_naughty ) {
        die $log->critical("Suspicious module ($file)");
    }

    $archive->extract($target);

    # Determine if this is a directory in and of itself
    # or whether it's just a bunch of files
    # (This is what Archive::Any refers to as "impolite")
    # It has to be done manually, because the list of files
    # from an archive might return an empty directory listing
    # or none, which confuses us
    my @files = $target->children();
    if ( @files == 1 && $files[0]->is_dir ) {
        # Polite
        return $files[0];
    }

    # Is impolite, meaning it's just a bunch of files
    # (or a single file, but still)
    return $target;
}

sub create_spec_for {
    my ( $self, $type, $name, $requirements ) = @_;
    return if $self->skip_name($name);
    return if $self->processed_dists->{ $name }++;

    my $release = $self->get_release_info($type, $name, $requirements);
    return if exists $release->{'skip'};

    my $dist_name    = $release->{'distribution'};
    my $rel_version  = $release->{'version'};

    $log->infof( '%sWorking on %s (%s)', $self->spaces, $dist_name, $rel_version );

    my $index = $self->spec_index;

    if ( exists $index->{ $name } ) {
        if ( exists $index->{ $name }{ $rel_version } ) {
            $log->debugf( 'Skipping %s-%s (spec already exists in repo)', $name, $rel_version );
            return;
        }
        else {
            $log->debugf( 'We have the following versions for %s:', $name );
            $log->debugf( '- %s', $_ )
                for keys %{ $index->{ $name } };
            $log->debugf( 'Adding %s version %s', $name, $rel_version );
        }
    }

    my $package_spec = {
        'Package' => {
            'category' => 'perl',
            'name'     => $dist_name,
            'version'  => $rel_version,
            'release'  => 1, # hmm... ???
        },
    };

    my $package   = Pakket::Package->new_from_spec($package_spec);
    my $full_name = $package->full_name;

    $self->set_depth( $self->depth + 1 );


    # Source

    # check if we already have the source in the repo
    if ( $self->source_repo->has_object( $package->id ) ) {
        $log->debugf(
            "Package %s - source already exists in repo (skipping).",
            $full_name
        );

    } else {
        # Download if source doesn't exist in cache
        my $download     = 1;
        my $download_url = $self->rewrite_download_url( $release->{'download_url'} );

        if ( $self->_has_cache_dir ) {
            my $from_name = $download_url
                ? $download_url =~ s{^.+/}{}r
                : $dist_name . '-' . $rel_version . '.tar.gz';

            my $from_file = path( $self->cache_dir, $from_name );

            if ( $from_file->exists ) {
                $log->debugf(
                    'Found source for %s [%s]',
                    $full_name, $from_file->stringify
                );

                my $target = Path::Tiny->tempdir();
                my $dir    = $self->unpack( $target, $from_file );

                $self->source_repo->store_package_source(
                    $package, $dir,
                );

                $download = 0;
            }
        }

        if ( $download ) {
            if ( $download_url ) {
                my $source_file = path(
                    $self->download_dir,
                    ( $download_url =~ s{^.+/}{}r )
                );

                $self->ua->mirror( $download_url, $source_file );

                my $target = Path::Tiny->tempdir();
                my $dir    = $self->unpack( $target, $source_file );

                $self->source_repo->store_package_source(
                    $package, $dir,
                );

            }
            else {
                $log->errorf( "--- can't find download_url for %s-%s", $dist_name, $rel_version );
            }
        }
    }


    # Spec

    if ( $self->spec_repo->retrieve_location( $full_name ) ) {
        $log->debugf(
            "Package %s - spec already exists in repo (skipping).",
            $full_name
        );

        return;
    }

    my $dep_modules = $release->{'prereqs'};
    my $dep_prereqs = CPAN::Meta::Prereqs->new( $dep_modules );

    # options: configure, develop, runtime, test
    for my $phase ( @{ $self->phases } ) {
        my $prereq_data = $package_spec->{'Prereqs'}{'perl'}{$phase} = +{};

        for my $dep_type (qw< requires recommends suggests >) {
            next unless is_hashref( $dep_modules->{ $phase }{ $dep_type } );

            my $dep_requirements = $dep_prereqs->requirements_for( $phase, $dep_type );

            for my $module ( keys %{ $dep_modules->{ $phase }{ $dep_type } } ) {
                next if $self->skip_name($module);

                my $rel = $self->get_release_info( module => $module, $dep_requirements );
                next if exists $rel->{'skip'};

                my $dist = $rel->{'distribution'};

                if ( exists $self->known_incorrect_dependencies->{ $package->name }{ $dist } ) {
                    $log->debugf( "%sskipping %s (known 'bad' dependency for %s)",
                                  $self->spaces, $dist, $package->name );
                    next;
                }

                $prereq_data->{ $dist } = +{
                    'version' => ( $rel->{'write_version_as_zero'} ? "0" : $rel->{'version'} )
                };
            }

            # recurse through those as well
            $self->create_spec_for( 'dist' => $_, $dep_requirements )
                for keys %{ $package_spec->{'Prereqs'}{'perl'}{$phase} };
        }
    }

    # We had a partial Package object
    # So now we have to recreate that package object
    # based on the full specs (including prereqs)
    $package = Pakket::Package->new_from_spec($package_spec);

    my $filename = $self->spec_repo->store_package_spec($package);

    $self->set_depth( $self->depth - 1 );

    $log->infof( '%sDone: %s (%s)', $self->spaces, $dist_name, $rel_version );
}

sub get_dist_name {
    my ( $self, $module_name ) = @_;

    # fist check if we can get it from 02packages
    exists $self->cpan_02packages->{$module_name}
        and return $self->cpan_02packages->{$module_name}{'distribution'};

    # fallback to metacpan check
    $module_name = $self->known_incorrect_name_fixes->{ $module_name }
        if exists $self->known_incorrect_name_fixes->{ $module_name };

    my $dist_name;

    eval {
        my $mod_url  = $self->metacpan_api . "/module/$module_name";
        my $response = $self->ua->get($mod_url);

        $response->{'status'} == 200
            and Carp::croak("Cannot fetch $mod_url");

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
            Carp::croak("Cannot find module by name: '$module_name'");
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

        is_arrayref( $res_body->{'hits'}{'hits'} )
            or Carp::croak("Can't find any release for $dist_name");

        %all_dist_releases =
            map {
                my $v = $_->{'fields'}{'version'};
                ( is_arrayref($v) ? $v->[0] : $v ) => {
                    'prereqs'      => $_->{'_source'}{'metadata'}{'prereqs'},
                    'download_url' => $_->{'_source'}{'download_url'},
                },
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
    my $rewrite = $self->config->{'perl'}{'metacpan'}{'rewrite_download_url'};
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

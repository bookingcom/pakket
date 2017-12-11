package Pakket::Scaffolder::Perl;
# ABSTRACT: Scffolding Perl distributions

use Moose;
use MooseX::StrictConstructor;
use version 0.77;
use Carp ();
use Archive::Any;
use CPAN::DistnameInfo;
use CPAN::Meta;
use CPAN::Meta::Prereqs;
use Parse::CPAN::Packages::Fast;
use JSON::MaybeXS       qw< decode_json encode_json >;
use Ref::Util           qw< is_arrayref is_hashref >;
use Path::Tiny          qw< path >;
use Types::Path::Tiny   qw< Path  >;
use Log::Any            qw< $log >;

use Pakket::Package;
use Pakket::Types;
use Pakket::Utils::Perl qw< should_skip_core_module >;
use Pakket::Constants   qw< PAKKET_PACKAGE_SPEC >;
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

has 'processed_packages' => (
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
    'isa'     => 'Parse::CPAN::Packages::Fast',
    'lazy'    => 1,
    'builder' => '_build_cpan_02packages',
);

has 'versioner' => (
    'is'      => 'ro',
    'isa'     => 'Pakket::Versioning',
    'lazy'    => 1,
    'builder' => '_build_versioner',
);

has 'no_deps' => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'default' => 0,
);

has 'no_bootstrap' => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'default' => 0,
);

has 'is_local' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'default' => sub { +{} },
);

has 'types' => (
    'is'      => 'ro',
    'isa'     => 'ArrayRef',
    'default' => sub { [qw< requires recommends suggests >] },
);

has 'dist_name' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'default' => sub { +{} },
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

sub _build_cpan_02packages {
    my $self = shift;
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

    return Parse::CPAN::Packages::Fast->new($file);
}

sub _build_versioner {
    return Pakket::Versioning->new( 'type' => 'Perl' );
}

sub BUILDARGS {
    my ( $class, @args ) = @_;
    my %args = @args == 1 ? %{ $args[0] } : @args;

    my $module   = delete $args{'module'};
    my $cpanfile = delete $args{'cpanfile'};

    Carp::croak("Please provide either 'module' or 'cpanfile'")
        unless $module xor $cpanfile;

    if ( $module ) {
        # hack to pass exact version in prereq syntax
        # add '==' before number of version
        my $version = $module->version
                        ? "== " . $module->version
                        : ">= 0";

        my ( $phase, $type   ) = delete @args{qw< phase type >};
        $args{'modules'} =
            Pakket::Scaffolder::Perl::Module->new(
                'name'    => $module->name,
                'version' => $version,
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
    if ( !$self->no_bootstrap and !$self->no_deps ) {
        my $requirements = $self->prereqs->requirements_for(qw< configure requires >);
        for my $package ( @{ $self->perl_bootstrap_modules } ) {
            $log->debugf( 'Bootstrapping toolchain: %s', $package );
            eval {
                $self->scaffold_package( $package, $requirements );
                1;
            } or do {
                my $err = $@ || 'zombie error';
                Carp::croak("Cannot bootstrap toolchain module: $package ($err)\n");
            };
        }
    }

    # the rest
    for my $phase ( @{ $self->phases } ) {
        for my $type ( @{ $self->types } ) {
            next unless is_hashref( $self->modules->{ $phase }{ $type } );

            my $requirements = $self->prereqs->requirements_for( $phase, $type );

            for my $package ( sort keys %{ $self->modules->{ $phase }{ $type } } ) {
                eval {
                    $self->scaffold_package( $package, $requirements );
                    1;
                } or do {
                    my $err = $@ || 'zombie error';
                    $failed{$package} = $err;
                };
            }
        }
    }

    my $errors = keys %failed;
    if ($errors) {
        for my $f ( sort keys %failed ) {
            $log->errorf( "[FAILED] %s: %s", $f, $failed{$f} );
        }
    } else {
        $log->info( 'Done' );
    }
    return $errors;
}

sub scaffold_package {
    my ( $self, $package_name, $requirements ) = @_;

    if ( $self->processed_packages->{ $package_name }++ ) {
        $log->debugf("Skipping $package_name, already processed");
        return;
    }

    if ( $self->is_package_in_spec_repo($package_name, $requirements) ) {
        return;
    }

    my $release_info = $self->get_release_info_for_package( $package_name, $requirements );

    my $package_spec = {
        'Package' => {
            'category' => 'perl',
            'name'     => $package_name,
            'version'  => $release_info->{'version'},
            'release'  => 1, # hmm... ???
        },
    };

    my $package = Pakket::Package->new_from_spec($package_spec);

    $log->debug( '----------------------------------------------' );
    $log->infof( '%sWorking on %s', $self->spaces, $package->full_name );
    $self->set_depth( $self->depth + 1 );

    # Source
    $self->add_source_for_package($package, $release_info);

    # Spec
    $self->add_spec_for_package($package, $release_info, $package_spec);

    $log->infof( '%sDone: %s', $self->spaces, $package->full_name );
    $self->set_depth( $self->depth - 1 );
}


sub add_source_for_package {
    my ($self, $package, $release_info) = @_;
    my $package_name = $package->name;

    # check if we already have the source in the repo
    if ( $self->source_repo->has_object( $package->id ) ) {
        $log->debugf("Package %s already exists in source repo (skipping)",
                        $package->full_name);
        return;
    }

    my $download_url = $self->rewrite_download_url( $release_info->{'download_url'} );

    if ( $self->_has_cache_dir ) {
        my $from_name = $download_url
            ? $download_url =~ s{^.+/}{}r
            : $package_name . '-' . $release_info->{'version'} . '.tar.gz';

        my $from_file = path( $self->cache_dir, $from_name );
        if ( $from_file->exists ) {
            $log->debugf( 'Found source for %s in %s',
                            $package_name, $from_file->stringify);

            $self->upload_source_archive( $package, $from_file );

            return;
        }
    }

    if ( $self->is_local->{$package_name} ) {
        Carp::croak( "IMPOSSIBLE: Can't find archive with source for %s", $package_name );
    }

    if ( !$download_url ) {
        Carp::croak( "Don't have download_url for %s", $package_name );
    }

    my $source_file = path( $self->download_dir,
                            ( $download_url =~ s{^.+/}{}r ) );
    $log->debugf("Downloading sources for %s (%s)", $package_name, $download_url);
    $self->ua->mirror( $download_url, $source_file );
    $self->upload_source_archive( $package, $source_file );
}

sub add_spec_for_package {
    my ($self, $package, $release_info, $spec) = @_;
    if ( $self->spec_repo->has_object( $package->id ) ) {
        $log->debugf("Package %s already exists in spec repo (skipping)",
                        $package->full_name);
        return;
    }
    $log->debugf("Creating spec for %s", $package->full_name);

    my $dep_prereqs = CPAN::Meta::Prereqs->new( $release_info->{'prereqs'} );

    my @dependencies_to_scaffold;

    for my $phase ( @{ $self->phases } ) {  # phases: configure, develop, runtime, test
        $spec->{'Prereqs'}{'perl'}{$phase} = +{};

        # CPAN requirement is a list of modules and their versions.
        # Pakket internally, in spec, keeps list of packages and their versions.
        # It is possible that few different modules from CPAN requirement are in one distribution.
        # We will gather distribution names and merge requirements of different modules of one distribution.
        my $spec_req = CPAN::Meta::Requirements->new;

        for my $dep_type ( @{ $self->types } ) {  # dep_type: requires, recommends
            next unless is_hashref( $release_info->{'prereqs'}->{ $phase }{ $dep_type } );
            my $dep_requirements = $dep_prereqs->requirements_for( $phase, $dep_type );

            for my $module ( keys %{ $release_info->{'prereqs'}->{ $phase }{ $dep_type } } ) {
                next if $self->skip_module($module);

                my $package_name = $self->get_dist_name($module);
                $log->debugf( "Found module $module in distribution $package_name" );

                if ( exists $self->known_incorrect_dependencies->{ $package->name }{ $package_name } ) {
                    $log->debugf( "%sskipping %s (known 'bad' dependency for %s)",
                                  $self->spaces, $package_name, $package->name );
                    next;
                }

                # TODO: find out correct way to translate module version to package version
                $spec_req->add_string_requirement( $package_name,
                            $dep_requirements->requirements_for_module($module) );
            }
        }

        my $spec_req_h = $spec_req->as_string_hash();
        for my $package_name ( keys %{ $spec_req_h } ) {
            push @dependencies_to_scaffold, [$package_name, $spec_req];
            $spec->{'Prereqs'}{'perl'}{$phase}->{ $package_name } =
                +{ 'version' => ( $spec_req_h->{ $package_name } || 0 ) };
        }
    }

    if ( ! $self->no_deps ) {
        $log->debugf( 'Scaffolding dependencies of %s', $package->full_name );
        for my $dependency (@dependencies_to_scaffold) {
            $self->scaffold_package( @{$dependency} );
        }
    }

    $self->merge_pakket_json_into_spec($package, $spec);

    # We had a partial Package object
    # So now we have to recreate that package object
    # based on the full specs (including prereqs)
    $package = Pakket::Package->new_from_spec($spec);

    $self->spec_repo->store_package_spec($package);
}

sub skip_module {
    my ( $self, $module_name ) = @_;

    if ( should_skip_core_module($module_name) ) {
        $log->debugf( "%sSkipping %s (core module, not dual-life)", $self->spaces, $module_name );
        return 1;
    }

    if ( exists $self->known_modules_to_skip->{ $module_name } ) {
        $log->debugf( "%sSkipping %s (known 'bad' module for configuration)", $self->spaces, $module_name );
        return 1;
    }

    return 0;
}

sub unpack {
    my ( $self, $target, $file ) = @_;

    my $archive = Archive::Any->new($file);

    if ( $archive->is_naughty ) {
        Carp::croak( $log->critical("Suspicious module ($file)") );
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

sub is_package_in_spec_repo {
    my ( $self, $package_name, $requirements ) = @_;

    my @versions = map { $_ =~ PAKKET_PACKAGE_SPEC(); $3 }
        @{ $self->spec_repo->all_object_ids_by_name($package_name, 'perl') };

    return 0 unless @versions; # there are no packages

    my $req_as_hash = $requirements->as_string_hash;
    if (!exists $req_as_hash->{$package_name}) {
        $log->debugf("Skipping %s, already have version: %s",
                        $package_name, join(", ", @versions));
        return 1;
    }

    if ($self->versioner->is_satisfying($req_as_hash->{$package_name}, @versions)) {
        $log->debugf("Skipping %s, already have satisfying version: %s",
                        $package_name, join(", ", @versions));
        return 1;
    }

    return 0; # spec has package, but version is not compatible
}

sub upload_source_archive {
    my ( $self, $package, $file ) = @_;

    my $target = Path::Tiny->tempdir();
    my $dir    = $self->unpack( $target, $file );

    $log->debugf("Uploading %s into source repo from %s", $package->name, $dir);
    $self->source_repo->store_package_source($package, $dir);
}

sub get_dist_name {
    my ( $self, $module_name ) = @_;

    # check if we've already seen it
    exists $self->dist_name->{$module_name}
        and return $self->dist_name->{$module_name};

    my $dist_name;

    # check if we can get it from 02packages
    eval {
        my $url = $self->metacpan_api . "/package/" . $module_name;
        $log->debug("Requesting information about module $module_name ($url)");
        my $res = $self->ua->get($url);

        $res->{'status'} == 200
            or Carp::croak("Cannot fetch $url");

        my $content = decode_json $res->{'content'};
        $dist_name = $content->{'distribution'};
        1;
    } or do {
        my $error = $@ || 'Zombie error';
        $log->debug($error);
    };

    # fallback 1:  local copy of 02packages.details
    if ( ! $dist_name ) {
        my $mod = $self->cpan_02packages->package($module_name);
        $mod and $dist_name = $mod->distribution->dist;
    }

    # fallback 2: metacpan check
    if ( ! $dist_name ) {
        $module_name = $self->known_incorrect_name_fixes->{ $module_name }
            if exists $self->known_incorrect_name_fixes->{ $module_name };

        eval {
            my $mod_url  = $self->metacpan_api . "/module/$module_name";
            $log->debug("Requesting information about module $module_name ($mod_url)");
            my $response = $self->ua->get($mod_url);

            $response->{'status'} == 200
                or Carp::croak("Cannot fetch $mod_url");

            my $content = decode_json $response->{'content'};
            $dist_name  = $content->{'distribution'};
            1;
        } or do {
            my $error = $@ || 'Zombie error';
            $log->debug($error);
        };
    }

    # fallback 3: check if name matches a distribution name
    if ( ! $dist_name ) {
        eval {
            $dist_name = $module_name =~ s/::/-/rgsmx;
            my $url = $self->metacpan_api . '/release';
            $log->debug("Requesting information about distribution $dist_name ($url)");
            my $res = $self->ua->post( $url,
                                       +{ 'content' => $self->get_is_dist_name_query($dist_name) }
                                   );
            $res->{'status'} == 200 or Carp::croak();

            my $res_body = decode_json $res->{'content'};
            $res_body->{'hits'}{'total'} > 0 or Carp::croak();

            1;
        } or do {
            $log->warn("Cannot find distribution for module $module_name. Trying to use $dist_name as fallback");
        };
    }

    $dist_name and
        $self->dist_name->{$module_name} = $dist_name;

    return $dist_name;
}

sub get_release_info_local {
    my ( $self, $package_name, $requirements ) = @_;

    my $req = $requirements->as_string_hash;
    my $ver = $req->{$package_name} =~ s/^[=\ ]+//r;
    my $prereqs;
    my $from_file = path( $self->cache_dir, $package_name . '-' . $ver . '.tar.gz' );
    if ( $from_file->exists ) {
        my $target = Path::Tiny->tempdir();
        my $dir    = $self->unpack( $target, $from_file );
        $self->load_pakket_json($dir);
        if ( !$self->no_deps and
             ( $dir->child('META.json')->is_file or $dir->child('META.yml')->is_file )
        ) {
            my $file = $dir->child('META.json')->is_file
                ? $dir->child('META.json')
                : $dir->child('META.yml');
            my $meta = CPAN::Meta->load_file( $file );
            $prereqs = $meta->effective_prereqs->as_string_hash;
        } else {
            $log->warn("Can't find META.json or META.yml in $from_file");
        }
    } else {
        Carp::croak("Can't find source file $from_file for package $package_name");
    }

    return +{
        'distribution' => $package_name,
        'version'      => $ver,
        'prereqs'      => $prereqs,
    };
}

sub get_release_info_for_package {
    my ( $self, $package_name, $requirements ) = @_;

    # if is_local is set - generate info without upstream data
    if ( $self->is_local->{$package_name} ) {
        return $self->get_release_info_local( $package_name, $requirements );
    }

    # try the latest
    my $latest = $self->get_latest_release_info_for_distribution( $package_name );
    if ( $latest->{'version'} && defined $latest->{'download_url'}) {
        if ($requirements->accepts_module( $package_name => $latest->{'version'} )) {
            return $latest;
        }
        $log->debugf("Latest version of %s is %s. Doesn't satisfy requirements. Checking other old versions.",
                        $package_name, $latest->{'version'});
    }

    # else: fetch all release versions for this distribution
    my $release_prereqs;
    my $version;
    my $download_url;

    my $all_dist_releases = $self->get_all_releases_for_distribution($package_name);

    # get the matching version according to the spec

    my @valid_versions;
    for my $v ( keys %{$all_dist_releases} ) {
        eval {
            version->parse($v);
            push @valid_versions => $v;
            1;
        } or do {
            my $err = $@ || 'zombie error';
            $log->debugf( '[VERSION ERROR] distribution: %s, version: %s, error: %s',
                          $package_name, $v, $err );
        };
    }

    @valid_versions = sort { version->parse($b) <=> version->parse($a) } @valid_versions;

    for my $v ( @valid_versions ) {
        if ( $requirements->accepts_module($package_name => $v) ) {
            $version         = $v;
            $release_prereqs = $all_dist_releases->{$v}{'prereqs'} || {};
            $download_url    =
                $self->rewrite_download_url( $all_dist_releases->{$v}{'download_url'} );
            last;
        }
    }

    $version = $self->known_incorrect_version_fixes->{ $package_name } // $version;

    if (!$version) {
        Carp::croak("Cannot find a suitable version for $package_name requirements: "
                        . $requirements->requirements_for_module($package_name)
                        . ", available: " . join(', ', @valid_versions));
    }

    return +{
        'distribution' => $package_name,
        'version'      => $version,
        'prereqs'      => $release_prereqs,
        'download_url' => $download_url,
    };
}

sub get_all_releases_for_distribution {
    my ( $self, $distribution_name ) = @_;

    my $url = $self->metacpan_api . "/release";
    $log->debugf("Requesting release info for all old versions of $distribution_name ($url)");
    my $res = $self->ua->post( $url,
            +{ content => $self->get_release_query($distribution_name) });
    if ($res->{'status'} != 200) {
        Carp::croak("Can't find any release for $distribution_name from $url, Status: "
                . $res->{'status'} . ", Reason: " . $res->{'reason'} );
    }
    my $res_body = decode_json $res->{'content'};
    is_arrayref( $res_body->{'hits'}{'hits'} )
        or Carp::croak("Can't find any release for $distribution_name");

    my %all_releases =
        map {
            my $v = $_->{'fields'}{'version'};
            ( is_arrayref($v) ? $v->[0] : $v ) => {
                'prereqs'       => $_->{'_source'}{'metadata'}{'prereqs'},
                'download_url'  => $_->{'_source'}{'download_url'},
            },
        }
        @{ $res_body->{'hits'}{'hits'} };

    return \%all_releases;
}

sub rewrite_download_url {
    my ( $self, $download_url ) = @_;
    my $rewrite = $self->config->{'perl'}{'metacpan'}{'rewrite_download_url'};
    return $download_url unless is_hashref($rewrite);
    my ( $from, $to ) = @{$rewrite}{qw< from to >};
    return ( $download_url =~ s/$from/$to/r );
}

sub get_latest_release_info_for_distribution {
    my ( $self, $package_name ) = @_;

    my $url = $self->metacpan_api . "/release/$package_name";
    $log->debugf("Requesting release info for latest version of %s (%s)", $package_name, $url);
    my $res = $self->ua->get( $url );
    if ($res->{'status'} != 200) {
        $log->debugf("Failed receive from $url, Status: %s, Reason: %s", $res->{'status'}, $res->{'reason'});
        return;
    }

    my $res_body= decode_json $res->{'content'};
    my $version = $res_body->{'version'};
    $version = $self->known_incorrect_version_fixes->{ $package_name } // $version;

    return +{
            'distribution' => $package_name,
            'version'      => $version,
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

# parsing Pakket.json
# Packet.json should be in root directory of package, near META.json
# It keeps some settings which we are missing in META.json.
sub load_pakket_json {
    my ($self, $dir) = @_;
    my $pakket_json = $dir->child('Pakket.json');

    $pakket_json->exists or return;

    $log->debug("Found Pakket.json in $dir");

    my $data = decode_json($pakket_json->slurp_utf8);

    # Section 'module_to_distribution'
    # Using to map module->distribution for local not-CPAN modules
    if ($data->{'module_to_distribution'}) {
        for my $module_name ( keys %{$data->{'module_to_distribution'}}  ) {
            my $dist_name = $data->{'module_to_distribution'}{$module_name};
            $self->dist_name->{$module_name} = $dist_name;
        }
    }
    return $data;
}

sub merge_pakket_json_into_spec {
    my ($self, $package, $spec) = @_;

    my $src_dir = $self->source_repo->retrieve_package_source($package);

    my $pakket_json = $self->load_pakket_json($src_dir);

    if ($pakket_json->{'prereqs'}) {
        # package type: perl, native
        for my $type (keys %{$pakket_json->{'prereqs'}}) {
            # phase: runtime, configure
            for my $phase (keys %{$pakket_json->{'prereqs'}{$type}}) {
                for my $module (keys %{$pakket_json->{'prereqs'}{$type}{$phase}}) {
                    $spec->{'Prereqs'}{$type}{$phase}{$module}{'version'} =
                            $pakket_json->{'prereqs'}{$type}{$phase}{$module};
                }
            }
        }
    }

    if ($pakket_json->{'build_opts'}) {
        $spec->{'build_opts'} =  $pakket_json->{'build_opts'};
    }
}

__PACKAGE__->meta->make_immutable;
no Moose;
1;
__END__

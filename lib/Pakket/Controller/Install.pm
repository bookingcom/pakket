package Pakket::Controller::Install;

# ABSTRACT: Install pakket packages into an installation directory

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

# core
use Carp;
use English qw(-no_match_vars);
use Errno qw(:POSIX);
use experimental qw(declared_refs refaliasing signatures);

# non core
use File::Copy::Recursive qw(dircopy dirmove);
use JSON::MaybeXS qw(decode_json);
use Time::HiRes qw(time usleep);

# local
use Pakket::Constants qw(
    PARCEL_FILES_DIR
    PARCEL_METADATA_FILE
);
use Pakket::Log;
use Pakket::Type::Package;
use Pakket::Type::PackageQuery;
use Pakket::Type;
use Pakket::Utils qw(clean_hash is_writeable difference);
use Pakket::Utils::DependencyBuilder;

use constant {
    'SLEEP_TIME_USEC' => 1_000,
};

has [qw(no_prereqs)] => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'default' => 0,
);

has [qw(continue overwrite dry_run)] => (
    'is'      => 'ro',
    'isa'     => 'Int',
    'default' => 0,
);

has 'phases' => (
    'is'      => 'ro',
    'isa'     => 'ArrayRef[PakketPhase]',
    'default' => sub {+[qw(runtime)]},
);

has 'types' => (
    'is'      => 'ro',
    'isa'     => 'ArrayRef[PakketPrereqType]',
    'default' => sub {+[qw(requires)]},
);

has [qw(processing)] => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'lazy'    => 1,
    'clearer' => '_clear_processing',
    'default' => sub {+{}},
);

with qw(
    Pakket::Controller::Role::CanProcessQueries
    Pakket::Role::CanFilterRequirements
    Pakket::Role::CanUninstallPackage
    Pakket::Role::CanVisitPrereqs
    Pakket::Role::HasConfig
    Pakket::Role::HasInfoFile
    Pakket::Role::HasLibDir
    Pakket::Role::HasLog
    Pakket::Role::HasSpecRepo
    Pakket::Role::HasParcelRepo
    Pakket::Role::ParallelInstaller
);

sub execute ($self, %params) {
    $params{'prereqs'} && $params{'prereqs'}->%*
        and $params{'queries'} = $self->_parse_external_prereqs($params{'prereqs'});

    my @queries;
    foreach my $query ($params{'queries'}->@*) {
        $query->is_module()                                                    # no tidy
            and $query = $query->clone('name' => $self->determine_distribution($query->name));
        push (@queries, $query);
    }

    $self->dry_run && $self->dry_run == 1
        and return $self->_do_dry_run_simple(\@queries);

    $self->dry_run && $self->dry_run > 1
        and return $self->_do_dry_run_recursive(\@queries);

    my $_start = time;
    my $size   = @queries;
    my $result = $self->_do_install(\@queries);

    Pakket::Log::send_data({
            'severity' => $result ? 'warning' : 'info',
            'type'     => 'install',
            'version'  => $Pakket::Controller::Install::VERSION ? "$Pakket::Controller::Install::VERSION" : 'unknown',
            'count'    => int ($size),
            'is_force' => int (!!$self->overwrite),
            'result'   => int ($result),
        },
        $_start,
        time (),
    );

    return $result;
}

sub process_query ($self, $query, %params) {
    return;
}

sub install_parcel ($self, $package, $parcel_dir, $target_dir) {
    $self->log->info('Delivering parcel:', $package->id);
    $self->_move_parcel_dir($parcel_dir->child(PARCEL_FILES_DIR()), $target_dir);

    return;
}

sub _do_dry_run_simple ($self, $queries) {
    my (undef, \@not_found) = $self->filter_packages_in_cache(as_requirements($queries), $self->all_installed_cache);

    @not_found
        or return 0;

    say $_->id foreach @not_found;

    return E2BIG;
}

sub _do_dry_run_recursive ($self, $queries) {
    my \@packages = $self->_recursive_requirements($queries);

    @packages
        or return 0;

    say $_->id foreach @packages;

    return E2BIG;
}

sub _do_install ($self, $queries) {
    my \%requirements = as_requirements($queries);

    if (!$self->overwrite && $self->allow_rollback && $self->rollback_tag) {
        my $tags = $self->_get_rollback_tags();

        if (exists $tags->{$self->rollback_tag}) {
            $self->log->debugf(
                q{found dir '%s' with rollback_tag: %s},
                $tags->{$self->rollback_tag},
                $self->rollback_tag,
            );
            my $result = $self->activate_dir($tags->{$self->rollback_tag});
            if ($result && $result == EEXIST) {
                $self->log->notice('All packages already installed in active library with tag:', $self->rollback_tag);
            } else {
                $self->log->debug('Packages installed:', join (', ', map {$_->id} values %requirements));
                $self->log->info('Finished activating library with tag:', $self->rollback_tag);
            }
            return 0;
        }
    }

    is_writeable($self->libraries_dir)
        or croak($self->log->critical(q{Can't write to the installation directory:}, $self->libraries_dir));

    my %saved_requirements = %requirements;                                    # save requirements to test against them later
    $self->_check_against_installed(\%requirements, 0);
    %requirements
        or $self->log->notice('All packages are already installed')
        and return 0;

    $self->log->notice('Requested packages:', scalar keys %requirements);
    $self->push_to_data_consumer(\%requirements);

    $self->spawn_workers();

    $self->is_child                                                            # reinit backend after forking, this prevent problems with network backends
        and $self->reset_parcel_backend();

    $self->_fetch_packages();
    $self->wait_workers();

    $self->_check_fetch_failures();
    my $installed_count = $self->_install_packages(\%saved_requirements);

    $self->set_rollback_tag($self->work_dir, $self->rollback_tag);
    $self->activate_work_dir;

    #$self->log->info('Finished installing:', join (', ', map {$_->id} @packages));
    $self->log->noticef(q{Finished installing %d packages into: %s}, $installed_count, $self->pakket_dir);

    return 0;
}

sub _fetch_packages ($self) {
    my $dir         = $self->work_dir;
    my $dc_dir      = $self->data_consumer_dir;
    my $failure_dir = $self->data_consumer_dir->child('failed');

    $self->data_consumer->consume(
        sub ($consumer, $other_spec, $fh, $file) {
            eval {
                if (!$self->continue && $failure_dir->children) {
                    $consumer->halt;
                    $self->is_child
                        or $self->log->critical('Halting job early, some parcels cannot be fetched');
                }

                $self->log->trace('consuming file:', $file);
                my $file_contents = <$fh>;
                if (not $file_contents) {
                    $self->log->infof('Another worker got hold of the lock for %s first -- skipping', $file);
                    return $consumer->leave;
                }
                my $data = decode_json($file_contents);

                my $package
                    = Pakket::Type::Package->new_from_string($data->{'short_name'},
                    $data->%{qw(version release as_prereq)},
                    );

                $self->log->notice("Fetching parcel [$PID]:", $package->id, ('(as prereq)') x !!$package->as_prereq);

                my $parcel_dir = $self->parcel_repo->retrieve_package_file($package);
                $self->_process_prereqs($parcel_dir);

                dirmove($parcel_dir, $dc_dir->child('to_install' => $file))
                    or $self->croak($!);

                # It's actually faster to not hammer the filesystem checking for new
                # stuff. $consumer->consume will continue until `unprocessed` is empty,
                usleep SLEEP_TIME_USEC();
                1;
            } or do {
                chomp (my $error = $@ || 'zombie error');
                if ($self->continue) {
                    $self->log->warn('Consuming error:', $error);
                } else {
                    $consumer->halt;
                    $self->croak($error);
                }
            };
        },
    );

    my $stats = $self->data_consumer->runstats();
    return $stats->{'failed'};
}

sub _process_prereqs ($self, $parcel_dir) {
    $self->no_prereqs
        and return;

    my $specfile = $parcel_dir->child(PARCEL_FILES_DIR(), PARCEL_METADATA_FILE());
    my $package  = Pakket::Type::Package->new_from_specdata(decode_json($specfile->slurp_utf8));

    my $meta = $package->pakket_meta->prereqs
        or return;

    $self->log->infof(
        'Processing prereqs for: %s (%s)->(%s)',
        $package->id,
        join (',', $self->phases->@*),
        join (',', $self->types->@*),
    );

    my %requirements;
    $self->visit_prereqs(
        $meta,
        sub ($phase, $type, $name, $requirement) {
            $self->log->infof('Found prereq %9s %10s: %s=%s', $phase, $type, $name, $requirement);
            my $query = Pakket::Type::PackageQuery->new_from_string(
                "$name=$requirement",
                'as_prereq' => 1,
            );
            $requirements{$query->short_name} = $query;
        },
        'phases' => $self->phases,
        'types'  => $self->types,
    );

    $self->_check_against_installed(\%requirements, 1);

    $self->push_to_data_consumer(\%requirements);

    return;
}

sub _check_fetch_failures ($self) {
    my $failure_dir = $self->data_consumer_dir->child('failed');
    my @failed      = $self->data_consumer_dir->child('failed')->children;
    if (!$self->continue && @failed) {
        foreach my $file (@failed) {
            my $data = decode_json($file->slurp_utf8);
            $self->log->critical("Unable to fetch: $data->{'short_name'}=$data->{'version'}:$data->{'release'}");
        }
        $self->croak('Unable to fetch amount of parcels:', scalar @failed);
    }
    return;
}

sub _install_packages ($self, $saved_requirements) {
    my $dc_dir = $self->data_consumer_dir;

    my %packages;
    my %packages_cache;
    $dc_dir->child('processed')->visit(
        sub ($path, $state) {
            my $parcel_dir = $dc_dir->child('to_install', $path->basename, PARCEL_FILES_DIR());
            $parcel_dir->exists
                or croak($self->log->critical(q{Couldn't find dir where parcel was extracted:}, $parcel_dir));

            my $data      = decode_json($path->slurp_utf8);
            my $spec_file = $parcel_dir->child(PARCEL_METADATA_FILE());
            my $package   = Pakket::Type::Package->new_from_specdata(
                decode_json($spec_file->slurp_utf8),
                'as_prereq' => $data->{'as_prereq'},
            );

            exists $packages{$package->short_name}
                and carp('Package fetched several times: ', $package->id);

            $packages{$package->short_name} = {
                'package'    => $package,
                'parcel_dir' => $parcel_dir,
            };
            $packages_cache{$package->short_name}{$package->version}{$package->release} = undef;
        },
    );

    # check here that required versions are not spoiled during dependency resolve
    my @requirements_not_to_install = difference([keys $saved_requirements->%*], [keys %packages_cache]);
    delete $saved_requirements->@{@requirements_not_to_install};
    my (undef, \@not_found) = $self->filter_packages_in_cache($saved_requirements, \%packages_cache);
    if (@not_found) {
        $self->log->critical('Required package is spoiled by some prereq:', $_->id) for @not_found;
        $self->log->critical('You have inconsistency between required and prereq versions');
    }

    my $info_file = $self->load_info_file($self->work_dir);
    foreach my $short_name (sort keys %packages) {
        my $package = $packages{$short_name}{'package'};

        # uninstall previous version of the package
        my $package_to_upgrade = $self->_package_to_upgrade($package);
        $package_to_upgrade
            and $self->uninstall_package($info_file, $package_to_upgrade);

        $self->log->notice('Delivering parcel', $package->id);
        $self->add_package_to_info_file(
            'parcel_dir' => $packages{$short_name}{'parcel_dir'},
            'info_file'  => $info_file,
            'package'    => $package,
            'as_prereq'  => $package->as_prereq,
        );
        $self->_move_parcel_dir($packages{$short_name}{'parcel_dir'}, $self->work_dir);
    }
    $self->save_info_file($self->work_dir, $info_file);

    $dc_dir->remove_tree({'safe' => 0});

    return scalar %packages;
}

sub _move_parcel_dir ($self, $parcel_dir, $work_dir) {
    foreach my $item ($parcel_dir->children) {
        my $basename = $item->basename;

        $basename eq PARCEL_METADATA_FILE()                                    # (compatibility) metadata file should be placed in a smarter way
            and next;

        my $target_dir = $work_dir->child($basename);
        local $File::Copy::Recursive::RMTrgFil = 1; ## no critic [Perl::Critic::Policy::Variables::ProhibitPackageVars]
        dircopy($item, $target_dir)
            or croak($self->log->criticalf("Can't copy $item to $target_dir ($!)"));
    }

    return;
}

sub _check_against_installed ($self, $requirements, $level) {
    $requirements->%* && ($self->overwrite <= $level)
        or return;

    $self->log->debug('checking which packages are already installed...');
    my (\@installed, undef) = $self->filter_packages_in_cache($requirements, $self->all_installed_cache);
    $self->log->info('Package is already installed:', $_->id) foreach @installed;

    return \@installed;
}

sub _get_rollback_tags ($self) {
    my @dirs = grep {$_->basename ne 'active' && $_->is_dir} $self->libraries_dir->children;

    my %result;
    foreach my $dir (@dirs) {
        my $tag = $self->get_rollback_tag($dir)
            or next;
        $result{$tag} = $dir;
    }

    return \%result;
}

sub _package_to_upgrade ($self, $package) {
    my $query             = Pakket::Type::PackageQuery->new($package->%{qw(category name)});
    my $installed_package = $self->select_best_package($query, $self->all_installed_cache->{$package->short_name});
    if ($installed_package) {
        if ($package->variant eq $installed_package->variant) {
            $self->log->notice('Going to reinstall:', $package->id);
        } else {
            $self->log->notice('Going to replace', $installed_package->id, 'with', $package->id);
        }
        return $installed_package;
    }
    return;
}

sub _recursive_requirements ($self, $queries) {
    my $dependency_builder = Pakket::Utils::DependencyBuilder->new(
        $self->%{qw(log log_depth)},
        'spec_repo' => $self->spec_repo,
    );
    my \%requirements = $dependency_builder->recursive_requirements(
        $queries,
        'parcel_repo' => $self->parcel_repo,
        'phases'      => $self->phases,
        'types'       => $self->types,
    );

    return $dependency_builder->validate_requirements(\%requirements);
}

before [qw(install_parcel)] => sub ($self, @) {
    return $self->log_depth_change(+1);
};

after [qw(install_parcel)] => sub ($self, @) {
    return $self->log_depth_change(-1);
};

__PACKAGE__->meta->make_immutable;

1;

__END__

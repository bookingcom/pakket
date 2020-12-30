package Pakket::Role::HasInfoFile;

# ABSTRACT: Functions to work with 'info.json'

use v5.22;
use Moose::Role;
use namespace::autoclean;

# core
use Carp;
use List::Util qw(uniq);
use experimental qw(declared_refs refaliasing signatures switch);

# non core
use JSON::MaybeXS qw(decode_json encode_json);

# local
use Pakket::Constants qw(PAKKET_INFO_FILE PARCEL_METADATA_FILE);
use Pakket::Type::Package;

has 'all_installed_cache' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'lazy'    => 1,
    'builder' => '_build_all_installed_cache',
);

sub add_package_to_info_file ($self, %params) {
    _validate_install_info($params{'info_file'});

    my $package       = $params{'package'};
    my $prereqs       = $package->has_meta ? $package->pakket_meta->prereqs : undef;
    my \%install_info = $params{'info_file'};

    $params{'parcel_dir'}->visit(
        sub ($path, $state) {
            $path->is_file
                or return;

            my $filename = $path->relative($params{'parcel_dir'});
            $filename eq PARCEL_METADATA_FILE() || $filename->basename eq 'perllocal.pod'
                and return;

            my \@file_owners = $install_info{'files'}{$filename->stringify} //= [];
            push (@file_owners, $package->short_name);
            @file_owners = uniq @file_owners;

            if (@file_owners > 1) {
                $self->log->warn("File '$filename' intersection detected:", @{[@file_owners]});
            }
        },
        {'recurse' => 1},
    );

    $install_info{'packages'}{$package->short_name} = {
        'version'   => $params{'package'}->version,
        'release'   => $params{'package'}->release,
        'as_prereq' => int !!$params{'as_prereq'},
        ('prereqs' => $prereqs) x !!($prereqs && $prereqs->%*),
    };

    return;
}

sub remove_package_from_info_file ($self, $install_info, $package) {
    _validate_install_info($install_info);

    my @files;
    foreach my $file (keys $install_info->{'files'}->%*) {
        my @owners = grep {$_ ne $package->short_name} $install_info->{'files'}{$file}->@*;
        if (@owners) {
            @owners == $install_info->{'files'}{$file}->@*
                or $install_info->{'files'}{$file} = \@owners;
        } else {
            delete $install_info->{'files'}{$file};
            push (@files, $file);
        }
    }

    my $package_data = delete $install_info->{'packages'}{$package->short_name};
    $package_data->{'files'} = \@files;

    return $package_data;
}

sub set_rollback_tag ($self, $dir, $tag) {
    my $install_info = $self->load_info_file($dir);

    $install_info->{'descriptor'}{'rollback_tag'} = $tag;

    $self->save_info_file($dir, $install_info);

    return;
}

sub get_rollback_tag ($self, $dir) {
    my $install_info = $self->load_info_file($dir);

    return $install_info->{'descriptor'}{'rollback_tag'} // '';
}

sub load_info_file ($self, $dir) {
    my $path = $dir->child(PAKKET_INFO_FILE());

    my $result
        = $path->exists
        ? decode_json($path->slurp_utf8)
        : {'descriptor' => {'version' => 2}};

    return _normalize_install_info($result);
}

sub save_info_file ($self, $dir, $install_info) {
    _validate_install_info($install_info);

    my $path = $dir->child(PAKKET_INFO_FILE());
    $path->spew_utf8(encode_json($install_info));

    return;
}

sub all_installed_packages ($self, $dir = $self->active_dir) {
    my @result;

    my $install_info = $self->load_info_file($dir);
    exists $install_info->{'packages'}
        or return \@result;

    my \%packages = $install_info->{'packages'};
    for my $short_name (keys %packages) {
        my \%p = $packages{$short_name};
        push (@result, "${short_name}=$p{'version'}:$p{'release'}");
    }

    return \@result;
}

sub _build_all_installed_cache ($self) {
    my %result;

    my $install_info = $self->load_info_file($self->active_dir);
    exists $install_info->{'packages'}
        or return \%result;

    my \%packages = $install_info->{'packages'};

    for my $short_name (keys %packages) {
        my \%p = $packages{$short_name};
        $result{$short_name}{$p{'version'}}{$p{'release'}}++;
    }

    return \%result;
}

sub _validate_install_info ($install_info) {
    $install_info->{'descriptor'}{'version'} == 2
        or croak 'Incorrect info file version';

    return;
}

sub _normalize_install_info ($install_info) {
    if (!defined $install_info->{'descriptor'}{'version'}) {
        $install_info->{'descriptor'}{'version'} = 2;
        delete $install_info->{'installed_files'};                             # (compatibility) not creating these objects any more, just cleaning old
        delete $install_info->{'rollback_tag'};
        if ($install_info->{'installed_packages'}) {
            my \%packages = delete $install_info->{'installed_packages'};
            foreach my $category (keys %packages) {
                foreach my $name (keys $packages{$category}->%*) {
                    my \%p         = $packages{$category}{$name};
                    my $files      = delete $p{'files'} // [];
                    my $short_name = "$category/$name";
                    $install_info->{'packages'}{$short_name} = \%p;
                    push ($install_info->{'files'}{$_}->@*, $short_name) foreach $files->@*;
                }
            }
        }
    }

    _validate_install_info($install_info);
    return $install_info;
}

1;

__END__

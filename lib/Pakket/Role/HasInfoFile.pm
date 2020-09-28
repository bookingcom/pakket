package Pakket::Role::HasInfoFile;

# ABSTRACT: Functions to work with 'info.json'

use v5.22;
use Moose::Role;
use namespace::autoclean;

# core
use Carp;
use experimental qw(declared_refs refaliasing signatures switch);

# non core
use JSON::MaybeXS qw(decode_json);

# local
use Pakket::Constants qw(PAKKET_INFO_FILE PARCEL_METADATA_FILE);
use Pakket::Type::Package;
use Pakket::Utils qw(encode_json_pretty);

has 'all_installed_cache' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'lazy'    => 1,
    'builder' => '_build_all_installed_cache',
);

sub add_package_to_info_file ($self, %params) {
    my %files;
    $params{'parcel_dir'}->visit(
        sub ($path, $state) {
            $path->is_file
                or return;

            my $filename = $path->relative($params{'parcel_dir'});
            $filename eq PARCEL_METADATA_FILE()
                and return;

            $files{$filename} = {
                'category' => $params{'package'}->category,
                'name'     => $params{'package'}->name,
                'version'  => $params{'package'}->version,
                'release'  => $params{'package'}->release,
            };
        },
        {'recurse' => 1},
    );

    my $package = $params{'package'};
    my ($cat, $name) = ($package->category, $package->name);
    my $prereqs = $package->has_meta ? $package->pakket_meta->prereqs : undef;
    $params{'info_file'}->{'installed_packages'}{$cat}{$name} = {
        'version'   => $params{'package'}->version,
        'release'   => $params{'package'}->release,
        'files'     => [sort keys %files],
        'as_prereq' => int !!$params{'as_prereq'},
        ('prereqs' => $prereqs) x !!($prereqs && $prereqs->%*),
    };

    return;
}

sub set_rollback_tag ($self, $dir, $tag) {
    my $install_data = $self->load_info_file($dir);

    $install_data->{'rollback_tag'} = $tag;

    $self->save_info_file($dir, $install_data);

    return;
}

sub get_rollback_tag ($self, $dir) {
    my $install_data = $self->load_info_file($dir);

    return $install_data->{'rollback_tag'} // '';
}

sub load_info_file ($self, $dir) {
    my $info_file = $dir->child(PAKKET_INFO_FILE());

    my $install_data
        = $info_file->exists
        ? decode_json($info_file->slurp_utf8)
        : {};

    return $install_data;
}

sub save_info_file ($self, $dir, $install_data) {
    delete $install_data->{'installed_files'};                                 # (compatibility) not creating these objects any more, just cleaning old

    my $info_file = $dir->child(PAKKET_INFO_FILE());

    $info_file->spew_utf8(encode_json_pretty($install_data));

    return;
}

sub load_installed_packages ($self, $dir) {
    my @result;

    my $install_data = $self->load_info_file($dir);
    exists $install_data->{'installed_packages'}
        or return \@result;

    my \%packages = $install_data->{'installed_packages'};
    for my $category (keys %packages) {
        for my $name (keys $packages{$category}->%*) {
            my \%p = $packages{$category}->{$name};
            push (@result, "${category}/${name}=$p{'version'}:$p{'release'}");
        }
    }
    return \@result;
}

sub _build_all_installed_cache ($self) {
    my %result;

    my $install_data = $self->load_info_file($self->active_dir);
    exists $install_data->{'installed_packages'}
        or return \%result;

    my \%packages = $install_data->{'installed_packages'};

    for my $category (keys %packages) {
        for my $name (keys $packages{$category}->%*) {
            my $short_name = "${category}/${name}";
            $self->_always_overwrite($short_name)
                and next;
            my \%p = $packages{$category}{$name};
            $result{$short_name}{$p{'version'}}{$p{'release'}}++;
        }
    }
    return \%result;
}

sub _always_overwrite ($self, $short_name) {                                   # these packages will not be discovered as installed
    state $default_packages = [qw(perl/Sub-Quote)];
    state $always_overwrite = {map {$_ => undef} @{$self->config->{'always-overwrite'} // $default_packages}};

    return exists $always_overwrite->{$short_name};
}

1;

__END__

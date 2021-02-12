package Pakket::Repository::Spec;

# ABSTRACT: A spec repository

use v5.22;
use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

# core
use Carp;
use experimental qw(declared_refs refaliasing signatures);

# non core
use JSON::MaybeXS ();

# local
use Pakket::Type::Package;
use Pakket::Utils qw(encode_json_pretty);

extends qw(Pakket::Repository);

has '_cache' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'default' => sub {+{}},
);

sub BUILDARGS ($class, %args) {
    $args{'type'} //= 'spec';

    return Pakket::Role::HasLog->BUILDARGS(%args); ## no critic [Modules::RequireExplicitInclusion]
}

sub retrieve_package ($self, $package) {
    return $self->retrieve_package_by_id($package->id);
}

sub retrieve_package_by_id ($self, $id) {
    if (exists $self->_cache->{$id}) {
        return $self->_cache->{$id};
    }

    my $spec = eval {                                                          # no tidy
        $self->retrieve_content($id);
    } or do {
        chomp (my $error = $@ || 'zombie error');
        croak($self->log->criticalf('Cannot fetch content for package: %s error: %s', $id, $error));
    };

    my $config = eval {                                                        # no tidy
        my $json       = JSON::MaybeXS->new('relaxed' => 1);
        my $config_raw = $json->decode($spec);
        exists $config_raw->{'content'}
            ? $json->decode($config_raw->{'content'})
            : $config_raw;
    } or do {
        chomp (my $error = $@ || 'zombie error');
        croak($self->log->critical('Cannot read spec properly:', $error));
    };

    return ($self->_cache->{$id} = $config);
}

sub store_package ($self, $package, $spec = undef) {
    $self->log->debug('storing', $self->type, 'to', $package->id);
    $self->store_content($package->id, encode_json_pretty($spec || $package->spec));

    $self->add_to_cache($package->short_name, $package->version, $package->release);

    return;
}

sub gen_package ($self, $package) {
    my $spec = $self->retrieve_package($package);
    return Pakket::Type::Package->new_from_specdata($spec, $package->%{qw(as_prereq)});
}

__PACKAGE__->meta->make_immutable;

1;

__END__

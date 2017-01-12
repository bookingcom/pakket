package Pakket::Repository;
# ABSTRACT: Build in-memory representation of repo

use Moose;
use MooseX::StrictConstructor;

use Log::Any      qw< $log >;
use Pakket::Types qw< PakketRepositoryBackend >;

has 'backend' => (
    'is'       => 'ro',
    'does'     => 'PakketRepositoryBackend',
    'coerce'   => 1,
    'required' => 1,
    'handles'  => [ qw< latest_version packages_list > ],
);

__PACKAGE__->meta->make_immutable;
no Moose;

1;

__END__

=pod

package Pakket::Repository::Backend::File;
# ABSTRACT: A file-based backend repository

use Moose;
use MooseX::StrictConstructor;

use JSON::MaybeXS             qw< decode_json >;
use Path::Tiny                qw< path >;
use Log::Any                  qw< $log >;
use Types::Path::Tiny         qw< Path >;

with qw< Pakket::Role::Repository::Backend >;

has 'filename' => (
    'is'       => 'ro',
    'isa'      => Path,
    'coerce'   => 1,
    'required' => 1,
);

sub create_index {
    my $self     = shift;
    my $filename = $self->filename;

    my $file = path($filename);
    if ( !defined $file ) {
        $log->critical("File '$file' does not exist or cannot be read");
        exit 1;
    }

    return $file->slurp_utf8;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

__END__

=pod

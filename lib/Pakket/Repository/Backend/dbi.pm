package Pakket::Repository::Backend::dbi;

# ABSTRACT: A DBI-based backend repository

# FIXME: Add methods: remove_location, remove_content

use v5.22;
use Moose;
use MooseX::StrictConstructor;

use Carp qw< croak >;
use DBI qw< :sql_types >;
use Types::DBI;
use Path::Tiny qw< path >;
use Log::Any qw< $log >;

with qw<
    Pakket::Role::Repository::Backend
>;

has 'dbh' => (
    'is'       => 'ro',
    'isa'      => Dbh,
    'required' => 1,
    'coerce'   => 1,
);

sub new_from_uri {
    my ($class, $uri) = @_;
    return $class->new('dbh' => $uri);
}

## no critic qw(Variables::ProhibitPackageVars)
sub all_object_ids {
    my $self = shift;
    my $sql  = q{SELECT id FROM data};
    my $stmt = $self->_prepare_statement($sql);

    if (!$stmt->execute()) {
        croak($log->criticalf('Could not get remote all_object_ids: %s', $DBI::errstr));
    }

    my @all_object_ids = map +($_->[0]), @{$stmt->fetchall_arrayref()};
    return \@all_object_ids;
}

sub all_object_ids_by_name {
    my ($self, $name, $category) = @_;

    croak($log->criticalf('Could not get remote all_object_ids_by_name: not implemented yet'));

    return '';
}

sub _prepare_statement {
    my ($self, $sql) = @_;
    my $stmt = $self->dbh->prepare($sql);

    if (!$stmt) {
        croak($log->criticalf('Could not prepare statement [%s] => %s', $sql, $DBI::errstr));
    }

    return $stmt;
}

sub has_object {
    my ($self, $id) = @_;
    my $sql  = q{ SELECT id FROM data WHERE id = ? };
    my $stmt = $self->_prepare_statement($sql);

    $stmt->bind_param(1, $id, SQL_VARCHAR);
    if (!$stmt->execute()) {
        croak($log->criticalf('Could not retrieve content for id %d: %s', $id, $DBI::errstr));
    }

    my $results = $stmt->fetchall_arrayref();
    return @{$results} == 1;
}

sub store_location {
    my ($self, $id, $file_to_store) = @_;
    my $content = path($file_to_store)->slurp({'binmode' => ':raw'});
    $self->store_content($id, $content);
}

sub retrieve_location {
    my ($self, $id) = @_;
    my $content  = $self->retrieve_content->($id);
    my $location = Path::Tiny->tempfile;
    $location->spew({'binmode' => ':raw'}, $content);
    return $location;
}

sub store_content {
    my ($self, $id, $content) = @_;
    {
        my $sql  = q{DELETE FROM data WHERE id = ?};
        my $stmt = $self->_prepare_statement($sql);

        $stmt->bind_param(1, $id, SQL_VARCHAR);
        if (!$stmt->execute()) {
            croak($log->criticalf('Could not delete content for id %d: %s', $id, $DBI::errstr));
        }
    }
    {
        my $sql  = q{INSERT INTO data (id, content) VALUES (?, ?)};
        my $stmt = $self->_prepare_statement($sql);

        $stmt->bind_param(1, $id,      SQL_VARCHAR);
        $stmt->bind_param(2, $content, SQL_BLOB);
        if (!$stmt->execute()) {
            croak($log->criticalf('Could not insert content for id %d: %s', $id, $DBI::errstr));
        }
    }
}

sub retrieve_content {
    my ($self, $id) = @_;
    my $sql  = q{SELECT content FROM data WHERE id = ?};
    my $stmt = $self->_prepare_statement($sql);

    $stmt->bind_param(1, $id, SQL_VARCHAR);
    if (!$stmt->execute()) {
        croak($log->criticalf('Could not retrieve content for id %d: %s', $id, $DBI::errstr));
    }

    my $all_content = $stmt->fetchall_arrayref();
    if (!$all_content || @{$all_content} != 1) {
        croak($log->criticalf('Failed to retrieve exactly one row for id %d: %s', $id));
    }

    return $all_content->[0];
}

sub remove_location {
    my ($self, $id) = @_;

    croak($log->criticalf('Could not get remote all_object_ids_by_name: not implemented yet'));

    return 1;
}

sub remove_content {
    my ($self, $id) = @_;
    return $self->remove_location($id);
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

__END__

=pod

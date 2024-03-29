package Pakket::Controller::Role::CanProcessQueries;

# ABSTRACT: Role to process arrays of queries

use v5.22;
use Moose::Role;
use namespace::autoclean;

# core
use Errno        qw(:POSIX);
use experimental qw(declared_refs refaliasing signatures);

# local
use Pakket::Type::PackageQuery;
use Pakket::Type;

requires qw(
    process_query
);

with qw(
    Pakket::Role::CanVisitPrereqs
    Pakket::Role::Perl::HasCpan
);

has [qw(no_prereqs no_continue)] => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'default' => 0,
);

has [qw(failed succeeded)] => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'default' => sub {+{}},
);

has 'phases' => (
    'is'       => 'ro',
    'isa'      => 'ArrayRef[PakketPhase]',
    'required' => 1,
);

has 'types' => (
    'is'       => 'ro',
    'isa'      => 'ArrayRef[PakketPrereqType]',
    'required' => 1,
);

sub check_queries_before_processing (@) {return 1}
sub check_query (@)                     {return 1}

sub process_queries ($self, %params) {
    $params{'prereqs'} && $params{'prereqs'}->%*
        and $params{'queries'} = $self->_prepare_external_prereqs(delete $params{'prereqs'});

    my $queries = delete $params{'queries'};
    if ($self->check_queries_before_processing($queries, %params)) {
        $self->log->notice('Processing queries:', scalar $queries->@*);
        $self->_process_queries($queries, %params);
    }

    return $self->_finalize();
}

sub _process_queries ($self, $queries, %params) {
    foreach my $query ($queries->@*) {
        my $log_depth = $self->log_depth_get();
        eval {
            $query->is_module()                                                # no tidy
                and $query = $query->clone('name' => $self->determine_distribution($query->name));

            $self->check_query($query, %params) and $self->process_query($query, %params);

            1;
        } or do {
            ## no critic  [ErrorHandling::RequireCarping]
            $self->log_depth_set($log_depth);
            chomp (my $error = $@ || 'zombie error');
            $self->failed->{$query->short_name} = $error;
            $self->no_continue || $query->as_prereq
                ? die $error . "\n"
                : $self->log->warn($error);
        };
    }

    return;
}

sub _prepare_external_prereqs ($self, $prereqs) {
    my @queries;
    $self->visit_prereqs(
        $prereqs,
        sub ($phase, $type, $name, $requirement) {
            $self->log->noticef('Found %9s %10s: %s=%s', $phase, $type, $name, $requirement);
            push (@queries, Pakket::Type::PackageQuery->new_from_cpanfile($name, $requirement));
        },
        'phases' => $self->phases,
        'types'  => $self->types,
    );
    return \@queries;
}

sub process_prereqs ($self, $package, %params) {
    $self->no_prereqs || !$package->has_meta
        and return;

    my (\@phases, \@types) = @params{qw(phases types)};
    @phases && @types
        or $self->croak('Invalid empty phases or types');

    $self->log->infof('Checking prereqs for: %s (%s)->(%s)', $package->id, join (',', @phases), join (',', @types),);
    $self->log_depth_change(+1);
    my @queries;
    $self->visit_prereqs(
        $package->pakket_meta->prereqs,
        sub ($phase, $type, $module, $version) {
            my $query = Pakket::Type::PackageQuery->new_from_string(
                "$module=$version",
                'default_category' => 'perl',
                'as_prereq'        => 1,
            );
            $self->log->infof('Found %9s %10s: %s=%s', $phase, $type, $module, $version);
            push (@queries, $query);
        },
        'phases' => \@phases,
        'types'  => \@types,
    );
    $self->log_depth_change(-1);

    $self->log->noticef('Processing prereqs for: %s (%s)->(%s)', $package->id, join (',', @phases), join (',', @types));
    my $handler = $params{'handler'} // \&_process_queries;
    $handler->($self, \@queries, %params);
    $self->log->info('Processing prereqs done for:', $package->id);

    return;
}

sub _finalize ($self) {
    $self->log->notice('[SUCCESS]', $_) foreach sort keys $self->succeeded->%*;
    $self->succeeded->%*
        and $self->log->notice('Successfuly processed packages:', scalar $self->succeeded->%*);

    $self->failed->%*
        or return 0;

    $self->log->errorf('[FAIL] %s: %s', $_, $self->failed->{$_}) foreach sort keys $self->failed->%*;
    $self->log->critical('Failed to processed packages:', scalar $self->failed->%*);
    return ENOENT;
}

before [qw(_prepare_external_prereqs _process_queries)] => sub ($self, @) {
    return $self->log_depth_change(+1);
};

after [qw(_prepare_external_prereqs _process_queries)] => sub ($self, @) {
    return $self->log_depth_change(-1);
};

1;

__END__

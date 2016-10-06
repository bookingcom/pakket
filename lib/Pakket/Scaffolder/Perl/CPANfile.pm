package Pakket::Scaffolder::Perl::CPANfile;
# ABSTRACT: Scffolding Perl cpanfile reader

use Moose;

use Module::CPANfile;

has cpanfile => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has prereq_specs => (
    is      => 'ro',
    isa     => 'HashRef',
    lazy    => 1,
    builder => '_build_prereq_specs',
);

sub _build_prereq_specs {
    my $self = shift;
    my $file = Module::CPANfile->load($self->cpanfile);
    return $file->prereq_specs;
}


__PACKAGE__->meta->make_immutable;
no Moose;
1;
__END__

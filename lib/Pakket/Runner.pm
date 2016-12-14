package Pakket::Runner;

sub run {
    my ($self, %args) = @_;

    my $active_path = $args{'active_path'};

    local $ENV{PATH}            = "$active_path/bin:$ENV{PATH}";
    local $ENV{PERL5LIB}        = "$active_path/lib/perl5";
    local $ENV{LD_LIBRARY_PATH} = "$active_path/lib:$ENV{LD_LIBRARY_PATH}";

    system @args;
}

1;

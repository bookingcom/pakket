requires 'Algorithm::Diff::Callback';
requires 'App::Cmd';
requires 'Archive::Any';
requires 'CPAN::Meta::Requirements', '>= 2.140';
requires 'File::Basename';
requires 'File::Copy::Recursive';
requires 'File::Find';
requires 'File::HomeDir';
requires 'Getopt::Long', '>= 2.39';
requires 'Getopt::Long::Descriptive';
requires 'JSON::MaybeXS';
requires 'Log::Any', '>= 0.05';
requires 'Log::Any::Adapter::Dispatch', '>= 0.06';
requires 'Log::Dispatch';
requires 'Log::Dispatch::Screen::Color';
requires 'MetaCPAN::Client';
requires 'Module::CPANfile';
requires 'Module::Runtime';
requires 'Moose';
requires 'MooseX::StrictConstructor';
requires 'namespace::autoclean';
requires 'Path::Tiny';
requires 'Ref::Util';
requires 'System::Command';
requires 'Types::Path::Tiny';
requires 'version', '>= 0.77';
requires 'Archive::Tar::Wrapper';
requires 'Archive::Any';
requires 'Digest::SHA';

# For the HTTP backend
requires 'HTTP::Tiny';

# For the web service
requires 'Dancer2';
requires 'Dancer2::Plugin::ParamTypes';

# Only for the DBI backend
requires 'DBI';
requires 'Types::DBI';

on 'test' => sub {
    requires 'Test::Perl::Critic::Progressive';
};

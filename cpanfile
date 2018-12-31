requires 'Algorithm::Diff::Callback';
requires 'App::Cmd';
requires 'Archive::Any';
requires 'Archive::Extract';
requires 'Archive::Tar::Wrapper';
requires 'CPAN::DistnameInfo';
requires 'CPAN::Meta::Requirements', '>= 2.140';
requires 'Config::Any';
requires 'Digest::SHA';
requires 'File::Basename';
requires 'File::Copy::Recursive';
requires 'File::Find';
requires 'File::HomeDir';
requires 'File::Lockfile';
requires 'File::NFSLock';
requires 'File::chdir';
requires 'Getopt::Long', '>= 2.39';
requires 'Getopt::Long::Descriptive';
requires 'Git::Wrapper';
requires 'IO::Prompt::Tiny';
requires 'JSON::MaybeXS';
requires 'Log::Any', '>= 0.05';
requires 'Log::Any::Adapter::Dispatch', '>= 0.06';
requires 'Log::Dispatch';
requires 'MetaCPAN::Client';
requires 'Module::CPANfile';
requires 'Module::Runtime';
requires 'Moose';
requires 'MooseX::StrictConstructor';
requires 'Parse::CPAN::Packages::Fast';
requires 'Path::Tiny';
requires 'Ref::Util';
requires 'Regexp::Common';
requires 'System::Command';
requires 'Time::Format';
requires 'Time::HiRes';
requires 'Try::Tiny';
requires 'Types::Path::Tiny';
requires 'YAML';
requires 'namespace::autoclean';
requires 'version', '>= 0.77';

requires 'Log::Dispatch::Screen::Gentoo';
requires 'Term::GentooFunctions', '>= 1.3700';

# Optimizes Gentoo color output
requires 'Unicode::UTF8';

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
    requires 'Test::Vars';
};

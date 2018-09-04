requires 'Algorithm::Diff::Callback';
requires 'App::Cmd';
requires 'Archive::Any';
requires 'Archive::Extract';
requires 'IO::Prompt::Tiny';
requires 'CPAN::DistnameInfo';
requires 'CPAN::Meta::Requirements', '>= 2.140';
requires 'File::Basename';
requires 'File::chdir';
requires 'File::Copy::Recursive';
requires 'File::Find';
requires 'File::HomeDir';
requires 'File::NFSLock';
requires 'File::Lockfile';
requires 'Getopt::Long', '>= 2.39';
requires 'Getopt::Long::Descriptive';
requires 'Git::Wrapper';
requires 'JSON::MaybeXS';
requires 'Log::Any', '>= 0.05';
requires 'Log::Any::Adapter::Dispatch', '>= 0.06';
requires 'Log::Dispatch';
requires 'MetaCPAN::Client';
requires 'Module::CPANfile';
requires 'Module::Runtime';
requires 'Moose';
requires 'MooseX::StrictConstructor';
requires 'namespace::autoclean';
requires 'Path::Tiny';
requires 'Parse::CPAN::Packages::Fast';
requires 'Ref::Util';
requires 'Regexp::Common';
requires 'System::Command';
requires 'Types::Path::Tiny';
requires 'Time::HiRes';
requires 'Time::Format';
requires 'version', '>= 0.77';
requires 'Archive::Tar::Wrapper';
requires 'Digest::SHA';
requires 'YAML';
requires 'Config::Any';

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

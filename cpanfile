# vim: syntax=conf foldmethod=marker
# man: cpan

requires 'Algorithm::Diff::Callback';
requires 'App::Cmd';
requires 'Archive::Any';
requires 'Archive::Extract';
requires 'Archive::Tar::Wrapper';
requires 'CPAN::DistnameInfo';
requires 'CPAN::Meta::Requirements', '>= 2.140';
requires 'Config::Any';
requires 'Data::Consumer';
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
requires 'Log::Any';
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
requires 'IO::Socket::SSL';
requires 'Net::SSLeay';

# For the DBI backend
requires 'DBI';
requires 'Types::DBI';

# For the S3 backend
requires 'Net::Amazon::S3';
requires 'LWP::Protocol::https';

# For the web service
requires 'Dancer2';
requires 'Dancer2::Plugin::ParamTypes';

on 'test' => sub {
	requires 'Code::TidyAll';
	requires 'Module::Faker';
	requires 'MooseX::Test::Role';
	requires 'Perl::Critic::Bangs';
	requires 'Perl::Critic::Freenode';
	requires 'Perl::Critic::Itch';
	requires 'Perl::Critic::Lax';
	requires 'Perl::Critic::Moose';
	requires 'Perl::Critic::Policy::BuiltinFunctions::ProhibitDeleteOnArrays';
	requires 'Perl::Critic::Policy::BuiltinFunctions::ProhibitReturnOr';
	requires 'Perl::Critic::Policy::HTTPCookies';
	requires 'Perl::Critic::Policy::Moo::ProhibitMakeImmutable';
	requires 'Perl::Critic::Policy::Perlsecret';
	requires 'Perl::Critic::Policy::TryTiny::RequireBlockTermination';
	requires 'Perl::Critic::Policy::TryTiny::RequireUse';
	requires 'Perl::Critic::Policy::ValuesAndExpressions::PreventSQLInjection';
#	requires 'Perl::Critic::Policy::Variables::ProhibitUselessInitialization';
	requires 'Perl::Critic::PetPeeves::JTRAMMELL';
	requires 'Perl::Critic::Pulp';
	requires 'Perl::Critic::StricterSubs';
	requires 'Perl::Critic::Tics';
	requires 'Test::BOM';
	requires 'Test::EOL';
	requires 'Test::Perl::Critic::Progressive';
	requires 'Test::Pod';
	requires 'Test::Vars';
	requires 'Test2::Harness';
	requires 'Test2::Mock';
	requires 'Test2::Plugin::SpecDeclare';
	requires 'Test2::Tools::Spec';
	requires 'Test2::V0';
};

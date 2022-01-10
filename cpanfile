# This file is generated by Dist::Zilla::Plugin::CPANFile v6.024
# Do not edit this file directly. To change prereqs, edit the `dist.ini` file.

requires "Algorithm::Diff::Callback" => "0";
requires "App::Cmd::Setup" => "0";
requires "Archive::Any" => "0";
requires "Archive::Extract" => "0";
requires "Archive::Tar" => "0";
requires "CHI" => "0";
requires "CPAN::DistnameInfo" => "0";
requires "CPAN::Meta" => "0";
requires "Config::Any" => "0";
requires "DBI" => "0";
requires "Data::Consumer::Dir" => "0";
requires "Digest::SHA" => "0";
requires "Fatal" => "0";
requires "File::Copy::Recursive" => "0";
requires "File::HomeDir" => "0";
requires "File::Lockfile" => "0";
requires "File::ShareDir" => "0";
requires "File::Spec" => "0";
requires "File::chdir" => "0";
requires "Future::AsyncAwait" => "0";
requires "Git::Wrapper" => "0";
requires "HTTP::Tiny" => "0";
requires "IO::Interactive" => "0";
requires "IO::Prompt::Tiny" => "0";
requires "JSON::MaybeXS" => "0";
requires "LWP::Protocol::https" => "0";
requires "Log::Any" => "0";
requires "Log::Any::Adapter" => "0";
requires "Log::Any::Adapter::Dispatch" => "0";
requires "Log::Dispatch" => "0";
requires "Log::Dispatch::Screen::Gentoo" => "0";
requires "Module::CPANfile" => "0";
requires "Module::CoreList" => "0";
requires "Module::Runtime" => "0";
requires "Mojolicious" => "9.22";
requires "Mojolicious::Commands" => "0";
requires "Mojolicious::Plugin::OpenAPI" => "0";
requires "Mojolicious::Plugin::Status" => "0";
requires "Mojolicious::Plugin::SwaggerUI" => "0";
requires "Moose" => "0";
requires "Moose::Role" => "0";
requires "Moose::Util::TypeConstraints" => "0";
requires "MooseX::Clone" => "0";
requires "MooseX::StrictConstructor" => "0";
requires "Net::Amazon::S3" => "0";
requires "Net::Amazon::S3::Client" => "0";
requires "Net::Amazon::S3::Client::Object" => "0";
requires "POSIX" => "0";
requires "Parse::CPAN::Packages::Fast" => "0";
requires "Path::Tiny" => "0";
requires "Ref::Util" => "0";
requires "Safe::Isa" => "0";
requires "Sys::Syslog" => "0";
requires "System::Command" => "0";
requires "Time::Format" => "0";
requires "Time::HiRes" => "0";
requires "Types::DBI" => "0";
requires "Types::Path::Tiny" => "0";
requires "URI::Escape" => "0";
requires "Unicode::UTF8" => "0";
requires "YAML::XS" => "0";
requires "namespace::autoclean" => "0";
requires "namespace::clean" => "0";
requires "perl" => "v5.28.0";
requires "vars" => "0";
requires "version" => "0.77";

on 'build' => sub {
  requires "Module::Build" => "0.3601";
};

on 'test' => sub {
  requires "File::Spec" => "0";
  requires "IO::Handle" => "0";
  requires "IPC::Open3" => "0";
  requires "Module::Faker" => "0";
  requires "Module::Metadata" => "0";
  requires "MooseX::Test::Role" => "0";
  requires "Perl::Critic::Bangs" => "0";
  requires "Perl::Critic::Freenode" => "0";
  requires "Perl::Critic::Lax" => "0";
  requires "Perl::Critic::Moose" => "0";
  requires "Perl::Critic::Policy::Perlsecret" => "0";
  requires "Perl::Critic::Policy::TryTiny::RequireUse" => "0";
  requires "Perl::Critic::Pulp" => "0";
  requires "Perl::Critic::StricterSubs" => "0";
  requires "Perl::Critic::Tics" => "0";
  requires "Perl::Tidy" => "20211029";
  requires "Sys::Hostname" => "0";
  requires "Test2::Harness" => "0";
  requires "Test2::Suite" => "0";
  requires "Test2::Tools::Basic" => "0";
  requires "Test2::Tools::Spec" => "0";
  requires "Test2::V0" => "0";
  requires "Test::Mojo" => "0";
  requires "Test::More" => "0";
  requires "Test::Perl::Critic::Progressive" => "0";
  requires "Test::UseAllModules" => "0";
  requires "perl" => "v5.28.0";
};

on 'test' => sub {
  recommends "CPAN::Meta" => "2.120900";
};

on 'configure' => sub {
  requires "ExtUtils::MakeMaker" => "0";
  requires "File::ShareDir::Install" => "0.06";
  requires "Module::Build" => "0.3601";
  requires "perl" => "v5.28.0";
};

on 'develop' => sub {
  requires "Test::BOM" => "0";
  requires "Test::CPAN::Meta" => "0";
  requires "Test::CleanNamespaces" => "0.15";
  requires "Test::Code::TidyAll" => "0.50";
  requires "Test::EOF" => "0";
  requires "Test::EOL" => "0";
  requires "Test::More" => "0.88";
  requires "Test::NoBreakpoints" => "0.15";
  requires "Test::Pod" => "1.41";
  requires "Test::Spelling" => "0.12";
  requires "Test::Synopsis" => "0";
  requires "Test::TrailingSpace" => "0.0203";
  requires "Test::Version" => "1";
};

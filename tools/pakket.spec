%define debug_package  %{nil}

Name:           pakket
Version:        %{_upstream_version}
Release:        1%{?dist}
Summary:        pakket
License:        none
Group:          Development/Tools
Source:         %{name}.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:      x86_64
AutoReqProv:    no

%description
pakket

%prep

%setup -c -n %{name}-%{version}

%build

%install
rm -rf $RPM_BUILD_ROOT
mkdir -p $RPM_BUILD_ROOT/opt/pakket
cp -av * $RPM_BUILD_ROOT/opt/pakket/

%{_fixperms} $RPM_BUILD_ROOT/*

%check

%clean
rm -rf $RPM_BUILD_ROOT

%post
ln -s /opt/pakket/bin/pakket /usr/bin/pakket

%postun
rm /usr/bin/pakket

%files
%defattr(-,root,root,-)
/opt/pakket/*

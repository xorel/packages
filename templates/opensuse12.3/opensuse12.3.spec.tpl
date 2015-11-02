#
# spec file for package opennebula (Version 3.9.80)
# this code base is under development
#
# Copyright (c) 2010 SUSE LINUX Products GmbH, Nuernberg, Germany.
#
# All modifications and additions to the file contributed by third parties
# remain the property of their copyright owners, unless otherwise agreed
# upon. The license for this file, and modifications and additions to the
# file, is the same license as for the pristine package itself (unless the
# license for the pristine package is not an Open Source License, in which
# case the license is the MIT License). An "Open Source License" is a
# license that conforms to the Open Source Definition (Version 1.9)
# published by the Open Source Initiative.

# Please submit bugfixes or comments via http://bugs.opensuse.org/
#


Name:          %NAME%
Version:       %VERSION%
Release:       %PKG_VERSION%
License:       Apache-2.0
Summary:       Elastic Utility Computing Architecture
URL:           http://www.opennebula.org
Group:         Productivity/Networking/System

Source0:       %SOURCE%
Source1:       sunstone.init
Source8:       onetmpdirs
Source9:       xmlrpc-c.tar.gz
Source10:      build_opennebula.sh

BuildRequires: post-build-checks
BuildRequires: gcc-c++
BuildRequires: java-devel
BuildRequires: libcurl-devel
BuildRequires: libxml2-devel
BuildRequires: libxmlrpc-c-devel    >= 1.06
BuildRequires: libopenssl-devel     >= 0.9
BuildRequires: mysql-devel
BuildRequires: openssh
BuildRequires: pkg-config
BuildRequires: pwgen
BuildRequires: ruby                 >= 1.8.6
BuildRequires: scons                >= 0.97
BuildRequires: sqlite3-devel        >= 3.5.2
BuildRequires: xmlrpc-c             >= 1.06

%if 0%{?suse_version} > 1140
BuildRequires: systemd
%endif

Requires:      openssh
Requires:      openssl              >= 0.9
Requires:      pwgen
Requires:      ruby                 >= 1.8.6
Requires:      rubygem-json
Requires:      rubygem-sqlite3
Requires:      sqlite3              >= 3.5.2
Requires:      xmlrpc-c             >= 1.06

%{?systemd_requires}
Recommends:    mysql
Recommends:    nfs-kernel-server
Recommends:    rubygem-mysql
Recommends:    ypserv
BuildRoot:     %{_tmppath}/%{name}-%{version}-%{release}-root

%description
OpenNebula.org is an open-source project aimed at building the industry
standard open source cloud computing tool to manage the complexity and
heterogeneity of distributed data center infrastructures.

The OpenNebula.org Project is maintained and driven by the community. The
OpenNebula.org community has thousands of users, contributors, and supporters,
who interact through various online email lists, blogs and innovative projects
to support each other.

%package devel
Summary:  Development files for %{name}
Group:    Development/Libraries/Other
Requires: %{name} = %{version}

%description devel
The %{name} devel package contains man pages and examples.

%package sunstone
Summary: Browser based UI to administer an OpenNebulaCloud
Group:   Productivity/Networking/System
Requires: %{name} = %{version}
Requires: rubygem-nokogiri
Requires: rubygem-json
Requires: python

%description sunstone
sunstone if the web base UI to manage a deployed OpenNebula Cloud

%package java
Summary: Java interface to OpenNebula Cloud API
Group:   Productivity/Networking/System
Requires: java

%description java
Java interface to OpenNebula Cloud API

%prep
%setup -q

%build
# Uncompress xmlrpc-c and copy build_opennebula.sh
(
    cd ..
    tar xzvf %{SOURCE9}
    cp %{SOURCE10} .
)

#scons sqlite_db=/usr xmlrpc=/usr mysql=yes old_xmlrpc=yes %{?_smp_mflags}
../build_opennebula.sh
# Building java interface
cd src/oca/java
./build.sh -d

%install
export DESTDIR=%{buildroot}
export NO_BRP_CHECK_BYTECODE_VERSION=true
./install.sh
# Handle init system differences
%if 0%{?suse_version} > 1140
    install -p -D -m 755 share/pkgs/openSUSE/systemd/onedsetup %{buildroot}%{_sbindir}/onedsetup
    install -p -D -m 755 share/pkgs/openSUSE/systemd/one.service %{buildroot}%{_unitdir}/one.service
    install -p -D -m 755 share/pkgs/openSUSE/systemd/one_scheduler.service %{buildroot}%{_unitdir}/one_scheduler.service
    install -p -D -m 755 share/pkgs/openSUSE/systemd/sunstone.service %{buildroot}%{_unitdir}/sunstone.service

    install -p -D -m 755 share/pkgs/openSUSE/systemd/econe.service %{buildroot}%{_unitdir}/econe.service
    install -p -D -m 755 share/pkgs/openSUSE/systemd/oneflow.service %{buildroot}%{_unitdir}/oneflow.service
    install -p -D -m 755 share/pkgs/openSUSE/systemd/onegate.service %{buildroot}%{_unitdir}/onegate.service

%else
    %{__mkdir} %{buildroot}/etc/init.d
    %{__mv} %{buildroot}%{_bindir}/one %{buildroot}/etc/init.d
    install -p -D -m 755 %{SOURCE1} %{buildroot}%{_initrddir}/sunstone
%endif


%if 0%{?suse_version} > 1120 && 0%{?suse_version} <= 1140
    install -p -D -m 755 %{SOURCE8} %{buildroot}%{_sysconfdir}/tmpdirs.d/30_One
%endif

%if 0%{?suse_version} > 1140
    install -p -D -m 644 share/pkgs/openSUSE/systemd/onetmpdirs %{buildroot}/usr/lib/tmpfiles.d/one.conf
%endif

# sudoers
%{__mkdir} -p %{buildroot}%{_sysconfdir}/sudoers.d
install -p -D -m 440 share/pkgs/openSUSE/opennebula.sudoers %{buildroot}%{_sysconfdir}/sudoers.d/opennebula

install -p -D -m 644 src/oca/java/jar/org.opennebula.client.jar %{buildroot}%{_javadir}/org.opennebula.client.jar


%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root,-)
%doc LICENSE NOTICE
%config %{_sysconfdir}/one/auth
%config %{_sysconfdir}/one/cli
%config %{_sysconfdir}/one/defaultrc
%config %{_sysconfdir}/one/ec2query_templates
%config %{_sysconfdir}/one/econe.conf
%config %{_sysconfdir}/one/hm
#%config %{_sysconfdir}/one/im_ec2
%config %{_sysconfdir}/one/ec2_driver.conf
%config %{_sysconfdir}/one/ec2_driver.default
%config %{_sysconfdir}/one/oned.conf
%config %{_sysconfdir}/one/sched.conf
%config %{_sysconfdir}/one/vmm_*
%config %{_sysconfdir}/one/vmwarerc
%config %{_sysconfdir}/one/oneflow-server.conf
%config %{_sysconfdir}/one/onegate-server.conf
%config %{_sysconfdir}/sudoers.d/opennebula
%config %{_sysconfdir}/one/az_*
%config %{_sysconfdir}/one/sl_*


%if 0%{?suse_version} > 1120 && 0%{?suse_version} <= 1140
    %config %{_sysconfdir}/tmpdirs.d/30_One
%endif
%if 0%{?suse_version} > 1140
    %config /usr/lib/tmpfiles.d/one.conf
%endif
%{_bindir}/econe*
%{_bindir}/on*
%{_bindir}/mm_sched
%{_bindir}/novnc-server
%{_bindir}/tty_expect
/usr/lib/one/mads/*
/usr/lib/one/sh/scripts_common.sh
/usr/lib/one/ruby/*
/usr/lib/one/oneflow/*
/usr/lib/one/onegate/*
/var/lib/one/*
%if 0%{?suse_version} > 1140
    %{_sbindir}/onedsetup
    %{_unitdir}/one.service
    %{_unitdir}/one_scheduler.service
    %{_unitdir}/econe.service
    %{_unitdir}/oneflow.service
    %{_unitdir}/onegate.service
%else
    /etc/init.d/one
%endif
%dir %{_sysconfdir}/one
%dir /usr/lib/one
%dir /usr/lib/one/mads
%dir /usr/lib/one/ruby
%dir /usr/share/one
%dir /usr/lib/one/sh

%defattr(-, oneadmin, cloud, 0750)

%dir /var/lib/one
%dir /var/lib/one/datastores

%files devel
%defattr(-,root,root)
%doc README.md
%{_mandir}/man1/*
%{_datadir}/one/install_*
%{_datadir}/one/examples/*
%dir %{_datadir}/one
%dir %{_datadir}/one/examples

%files sunstone
%defattr(-,root,root,-)
%config %{_sysconfdir}/one/sunstone*
/usr/lib/one/sunstone/*
%if 0%{?suse_version} > 1140
    %{_unitdir}/sunstone.service
%else
    /etc/init.d/sunstone
%endif
%{_bindir}/sunstone-server
%{_datadir}/one/websockify/*
%dir /usr/lib/one/sunstone
%dir %{_datadir}/one/websockify

%files java
%defattr(-,root,root)
%{_javadir}/org.opennebula.client.jar


%pre
# cloud administrator setup
if ! getent passwd oneadmin &> /dev/null ; then
  echo "Creating oneadmin user"
  /usr/sbin/groupadd cloud
  ONEPWD=$(/usr/bin/pwgen 40 1)
  /usr/sbin/useradd -m -c "OpenNebula Cloud Admin" -d /var/lib/one -g cloud -p $ONEPWD oneadmin
fi

%post
if [ ! -d /var/lib/one/.ssh ] ; then
  %{__mkdir} /var/lib/one/.ssh
fi
# Setup the ssh infrastructure for the cloud
if [ ! -f /var/lib/one/.ssh/id_rsa ]; then
    /usr/bin/ssh-keygen -q -t rsa -f /var/lib/one/.ssh/id_rsa -N ''
fi
/bin/cp /var/lib/one/.ssh/id_rsa.pub /var/lib/one/.ssh/authorized_keys
echo "Host *" >> /var/lib/one/.ssh/config
echo "    StrictHostKeyChecking no" >> /var/lib/one/.ssh/config
# set the ownership of the management scripts
/bin/chown oneadmin:cloud      /var/lib/one
/bin/chown oneadmin:cloud      /var/lib/one/vms
/bin/chown oneadmin:cloud      /var/lib/one/datastores/0
/bin/chown oneadmin:cloud      /var/lib/one/datastores/1
/bin/chown -R oneadmin:cloud   /var/lib/one/remotes


if [ ! -d /var/log/one ]; then
  %{__mkdir} /var/log/one
fi
if [ ! -d /var/lock/one ]; then
  %{__mkdir} /var/lock/one
fi
/bin/chown -R oneadmin:cloud /var/log/one
/bin/chown -R oneadmin:cloud /var/lock/one

%changelog
* %DATE% %CONTACT% - %VERSION%
- Adapted the package from Robert Schweikert (rschweikert@suse.com)
* Wed Mar 27 2013 rschweikert@suse.com
- update to version 3.9.80 (3.4 beta)
- release notes: http://opennebula.org/software:rnotes:rn-rel4.0beta
* Tue Jan 22 2013 rschweikert@suse.com
- remove patch for issue 1619 (http://dev.opennebula.org/issues/1619),
  fix included
* Tue Jan 22 2013 rschweikert@suse.com
- update to version 3.8.3
- remove use of patch for issue 1619
- release notes: http://opennebula.org/software:rnotes:rn-rel3.8.3
* Thu Dec  6 2012 rschweikert@suse.com
- implement and include patch for issue 1683
  + this fixes issues with appliance creation and eliminates a confusing
    message when the DB is bootstrapped
  + note the mysql code changes for bootstrapping a mysql DB have not been
    tested, the sqlite changes have been tested
* Tue Dec  4 2012 rschweikert@suse.com
- clean up ruby dependencies
* Tue Oct 30 2012 rschweikert@suse.com
- update to version 3.8.1
- include patch for issue 1619 (http://dev.opennebula.org/issues/1619)
- see the migration guide for handling the necessary DB upgrade
  http://www.opennebula.org/documentation:rel3.8:upgrade
- Release notes: http://www.opennebula.org/software:rnotes:rn-rel3.8.1
- removed patches that were applied upstream
  openneb_64bitlib.patch openneb_startupdelaySunstone.patch
* Tue Oct 30 2012 rschweikert@suse.com
- fix factoy build, fix up call for build and install scripts for Java
  interface
* Wed Jul 18 2012 rschweikert@suse.com
- update to version 3.6.0
- for details see http://opennebula.org/software:rnotes:rn-rel3.6
- see the migration guide for handling the necessary DB upgrade
  http://www.opennebula.org/documentation:rel3.6:upgrade
- remove patches that were applied upstream
  openneb_onedsetupTimeout.patch, openneb_oneserviceConditions.patch,
  openneb_remotefsTargetName.patch, openneb_servicesUserSet.patch
  openneb_tmpdirsetup.patch
* Mon Jun 25 2012 rschweikert@suse.com
- update to 3.6.0 Beta 1
- for details see http://www.opennebula.org/software:rnotes:rn-rel3.6beta
- see the migration guide for handling the necessary DB upgrade
  http://www.opennebula.org/documentation:rel3.6:upgrade
* Thu Jun  7 2012 rschweikert@suse.com
- sync with spec from "stable" to ensure changes do not get
  lost for next testing version
* Tue May 15 2012 rschweikert@suse.com
- Delete obs .services files, use the files from upstream
- Add patches to modify upstream .services files
- Use the upstream file to create the tmpdirs on systemd
- Add patch to modify tmpdir setup file, fix syntax
* Tue May 15 2012 rschweikert@suse.com
- use the onedsetup script that is now upstream
* Mon May 14 2012 rschweikert@suse.com
- increase timeout for initial startup
* Fri May 11 2012 rschweikert@suse.com
- add sleep to service file to avoid race condition
  ~ upstream issue http://dev.opennebula.org/issues/1269
* Thu May  3 2012 rschweikert@suse.com
- bump to 3.4.1 bug fix release
* Thu Apr 26 2012 rschweikert@suse.com
- update to version 3.4
  ~ release notes: http://opennebula.org/software:rnotes:rn-rel3.4
* Sun Apr  8 2012 rschweikert@suse.com
- update to 3.3.80 (beta for 3.4 release)
  ~ release notes: http://www.opennebula.org/software:rnotes:rn-rel3.4beta
* Sun Apr  8 2012 rschweikert@suse.com
- update to 3.2.1 release
  ~ release notes: http://opennebula.org/software:rnotes:rn-rel3.2.1
  ~ fix 752437
    previous builds did not support using mysql as the DB to use for
    openNebula. This forced the user to stick with the light implementation
    this is undesirable behavior
  ~ fix 756144
    the openNebula services did not run with the proper permissions, i.e.
    ran as root instead of the oneadmin user. This created problems with
    node registration and other operations performed by the openNebula
    services
  ~ fix creation of temporary directories for systemd based systems
    temporary directories were not properly created on systems using systemd
    therefore openNebula services would fail to start on reboot.
  ~ this release will be pushed to the main repository
* Wed Jan 18 2012 rschweikert@suse.com
- update to 3.2 release
  ~ release notes: http://opennebula.org/software:rnotes:rn-rel3.2
  ~ this will not be pushed to the main project Virtualization:Cloud:OpenNebula
    there have been too many reports on the ML about issues with this release.
    The release is only a couple of days old and there have been at least 10
    reported issues.
* Sat Dec 31 2011 rschweikert@suse.com
- update to RC
  ~ release notes: http://www.opennebula.org/software:rnotes:rn-rel3.2beta
  ~ docs: http://www.opennebula.org/documentation:rel3.2
  ~ KNOWN ISSUE: VMWare drivers do not work
* Fri Dec 16 2011 rschweikert@suse.com
- build beta
  ~ release notes: http://www.opennebula.org/software:rnotes:rn-rel3.2beta
  ~ docs: http://www.opennebula.org/documentation:rel3.2
  ~ KNOWN ISSUE: VMWare drivers do not work
* Fri Dec  9 2011 rschweikert@suse.com
- initial build of 3.1.0
* Tue Dec  6 2011 rschweikert@suse.com
- do not create the lock file in the service unit
* Mon Dec  5 2011 rschweikert@suse.com
- tmpdirs mechanism does not exist in SLE, guard against
* Mon Dec  5 2011 rschweikert@suse.com
- set proper stop condition for scheduler; use TERM not HUP
- no need to remove .pid from unit file
* Mon Dec  5 2011 rschweikert@suse.com
- remove directory creation for temporary dirs from unit file and add
  them to the tempdirs mechanism.
* Mon Dec  5 2011 rschweikert@suse.com
- Fix up the services files:
  ~ one.services proper kill command
  ~ all services do not explicitely remove lock and pid files
- Fix initial setup of oned to kill the process properly for pid and
  lock file clean up
* Sun Dec  4 2011 rschweikert@suse.com
- export ONE_AUTH in sunstone init
- fix the one.service file to remove the lock
* Fri Dec  2 2011 rschweikert@suse.com
- additional zones dependencies
* Fri Dec  2 2011 rschweikert@suse.com
- add runtime dependencies for zones controller
* Fri Dec  2 2011 rschweikert@suse.com
- add zones integration for init and systemd
- put config files into the proper package
* Fri Dec  2 2011 rschweikert@suse.com
- fix syntax of onedsetup
* Fri Dec  2 2011 rschweikert@suse.com
- fix the service setup to properly handle the output redirection for
  the sunstone server
* Fri Dec  2 2011 rschweikert@suse.com
- systemd integration
* Mon Nov 28 2011 rschweikert@suse.com
- modify the initscript for the sunstone server to accomodate
  upstream code changes
* Sun Nov 27 2011 rschweikert@suse.com
- add requirement rubygem-sequel to sunstone
* Sun Nov 27 2011 rschweikert@suse.com
- do not use fdupes to avoid circular depends of ozones and sunstone
* Thu Nov 24 2011 rschweikert@suse.com
- initial build on 3.0 in :Testing project
* Thu Aug  4 2011 rschweikert@suse.com
- Make sure the onedamin home directory is properly created (-m on useradd)
* Wed Jul 13 2011 rschweikert@suse.com
- Modify the init scripts to use $network as required start not just network
- Add place holder for ONE_AUTH in sunstone init script
* Wed Jul 13 2011 rschweikert@suse.com
- eliminate warning about spec file on checkin
* Wed Jul 13 2011 rschweikert@suse.com
- Create new init script for sunstone rather than modifying existing script
  ~ remove patch modifying sunstone startup script
* Tue Jul 12 2011 rschweikert@suse.com
- Fix typo in sunstone dependency list
* Tue Jul 12 2011 rschweikert@suse.com
- add dir entry fix build error on SLE
* Tue Jul 12 2011 rschweikert@suse.com
- Set up sunstone package, webUI to administer the cloud
  ~ create page to turn the sunstone startup script into an init script
* Mon Jul 11 2011 rschweikert@suse.com
- Fix config dir spec to address rpmlint error on SLE 11
* Fri Jul  8 2011 rschweikert@suse.com
- Fix errors found by gcc 4.6.0
  ~ fix for const correctness
  ~ fix for using ref of temporary
* Fri Jun 17 2011 rschweikert@novell.com
- fix syntax error in post script
* Thu Jun 16 2011 rschweikert@novell.com
- setup the ssh files needed for the cloud from the package
* Mon Jun 13 2011 rschweikert@novell.com
- use pwgen instead of makepasswd, makepasswd does no longer exists on 11.4
* Mon Jun 13 2011 rschweikert@novell.com
- create oneadmin account with random password
* Fri Jun 10 2011 rschweikert@novell.com
- generate a random password for the oneadmin user
* Fri Jun 10 2011 rschweikert@novell.com
- fix the version number in the comment and bump the release number
  to reflect recent changes
* Fri Jun 10 2011 rschweikert@novell.com
- allow cloud group to be non unique, make it a system group
* Fri Jun 10 2011 rschweikert@novell.com
- create the oneadmin user as a system account
* Thu Jun  9 2011 rschweikert@novell.com
- remove backgrounding to get status for daemon correct
* Thu Jun  9 2011 rschweikert@novell.com
- bump to 2.2.1 for security fix, see
  http://lists.opennebula.org/pipermail/users-opennebula.org/2011-June/005570.html
* Thu Jun  9 2011 rschweikert@novell.com
- chown to oneadmin of /var/run/one
- start the daemon as oneadmin
* Thu Jun  9 2011 rschweikert@novell.com
- do not run chown on non existent dir
* Wed Jun  8 2011 rschweikert@novell.com
- set owenership of log, lock, and runtime dir to oneadmin user
* Fri Jun  3 2011 rschweikert@novell.com
- add LSB header to init script for oned, some cleanup
- move the initscript from /usr/bin to /etc/init.d
- fix the group for the devel package
* Thu Jun  2 2011 rschweikert@novell.com
- create lock file directory if it does not exist
* Wed Jun  1 2011 rschweikert@novell.com
- create log directory if it does not exist
* Tue May 31 2011 rschweikert@novell.com
- add patch to create logdir if it does not exist
* Mon May  2 2011 rschweikert@novell.com
- Fix typo in recommended package name
* Thu Apr 28 2011 rschweikert@novell.com
- Add the admin user for the cloud and the cloud group
- Change the permissions of files in the admin users home directory
- Add recommended packages
* Tue Apr 26 2011 rschweikert@novell.com
- Update version requirement for ruby
* Tue Apr 26 2011 rschweikert@novell.com
- Update to version 2.2
* Sun Feb 20 2011 rschweikert@novell.com
- Fix dependency name ssh -> openssh
* Fri Dec 31 2010 rschweikert@novell.com
- Claim appropriate directories as owned by this package
* Fri Dec 31 2010 rschweikert@novell.com
- Fix issues with the debug info, package nwo builds
* Wed Dec 29 2010 rschweikert@novell.com
- First cut at spec file and getting though build stage
  needs clean up w.r.t. file packaging to address rpmlint errors

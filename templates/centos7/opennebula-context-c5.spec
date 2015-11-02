# -------------------------------------------------------------------------- #
# Copyright 2002-2012, OpenNebula Project Leads (OpenNebula.org)             #
#                                                                            #
# Licensed under the Apache License, Version 2.0 (the "License"); you may    #
# not use this file except in compliance with the License. You may obtain    #
# a copy of the License at                                                   #
#                                                                            #
# http://www.apache.org/licenses/LICENSE-2.0                                 #
#                                                                            #
# Unless required by applicable law or agreed to in writing, software        #
# distributed under the License is distributed on an "AS IS" BASIS,          #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.   #
# See the License for the specific language governing permissions and        #
# limitations under the License.                                             #
#--------------------------------------------------------------------------- #

Name: opennebula-context
Summary: Configures a Virtual Machine for OpenNebula
Version: 3.8.1
Release: 0.1
License: Apache
Group: System
URL: http://opennebula.org

Source0: opennebula-%{version}.tar.gz
Source1: 01-dns
Source2: 02-ssh_public_key

BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root

################################################################################
# Requires
################################################################################

Requires: openssl
Requires: openssh
Requires: openssh-clients

################################################################################
# Main Package
################################################################################

Packager: OpenNebula Team <contact@opennebula.org>

%description
Configures a Virtual Machine for OpenNebula. In particular it configures the
udev rules, the network, and runs any scripts provided throught the CONTEXT
mechanism.


################################################################################
# Build and install
################################################################################

%prep
%setup -q -n opennebula-%{version}

%build

%install
export DESTDIR=%{buildroot}
./install.sh 2>/dev/null
%{__mkdir} -p %{buildroot}%{_initddir}

# Context packages
install -p -D -m 644 share/scripts/context-packages/base/etc/udev/rules.d/75-persistent-net-generator.rules \
        %{buildroot}%{_sysconfdir}/udev/rules.d/75-persistent-net-generator.rules
install -p -D -m 644 share/scripts/context-packages/base/etc/udev/rules.d/75-cd-aliases-generator.rules \
        %{buildroot}%{_sysconfdir}/udev/rules.d/75-cd-aliases-generator.rules
install -p -D -m 755 share/scripts/context-packages/base/etc/init.d/vmcontext \
        %{buildroot}%{_sysconfdir}/init.d/vmcontext
install -p -D -m 755 share/scripts/context-packages/base_rpm/etc/one-context.d/00-network \
        %{buildroot}%{_sysconfdir}/one-context.d/00-network
install -p -D -m 755 %{SOURCE1} \
        %{buildroot}%{_sysconfdir}/one-context.d/
install -p -D -m 755 %{SOURCE2} \
        %{buildroot}%{_sysconfdir}/one-context.d/

%clean
%{__rm} -rf %{buildroot}

%post

rm -f /etc/udev/rules.d/70-persistent-cd.rules
rm -f /etc/udev/rules.d/70-persistent-net.rules

/sbin/chkconfig --add vmcontext >/dev/null

rm -f /etc/sysconfig/network-scripts/ifcfg-eth*

################################################################################
# files
################################################################################

%files
%defattr(-,root,root,-)
%config %{_sysconfdir}/init.d/vmcontext
%config %{_sysconfdir}/one-context.d/*
%config %{_sysconfdir}/udev/rules.d/75-cd-aliases-generator.rules
%config %{_sysconfdir}/udev/rules.d/75-persistent-net-generator.rules

%exclude /var
%exclude /usr
%exclude %{_sysconfdir}/one

################################################################################
# Changelog
################################################################################

%changelog
* Tue Dec 04 2012 Jaime Melis <jmelis@opennebula.org> - 3.8.1-0.1
- Initial upload

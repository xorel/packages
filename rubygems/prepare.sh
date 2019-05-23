#!/bin/bash

# Copyright 2019, Erich Cernaj
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

if [ $# != 1 ]
then
  echo wrong number of arguments >&2
  echo choose debian or redhat >&2
  exit 1
fi

# Prepare array of packages and command install for chosen distribution

option="${1}"
case ${option} in
  "debian"|"-d")
    packages=("ruby-dev" "make" "gcc" "libsqlite3-dev" "libmysqlclient-dev" "libcurl4-openssl-dev" "rake" "libxml2-dev" "libxslt1-dev" "patch" "g++" "build-essential")
    install_command="apt-get -y install"
    ;;
  "redhat"|"-r")
    packages=("ruby-devel" "make" "gcc" "sqlite-devel" "mysql-devel" "openssl-devel" "curl-devel" "rubygem-rake" "libxml2-devel" "libxslt-devel" "patch" "expat-devel" "gcc-c++" "rpm-build")
    install_command="yum -y install"
    ;;
  "-h"|"help")
    echo install dependencies for gemtopackage.rb
    echo choose debian or redhat
    exit 0
  ;;
  *)
    echo unknown argument >&2
    exit 1
    ;;
esac

# Install packages

OK=0
for package in "${packages[@]}"
do
  echo installing $package
  $install_command $package >/dev/null
  if [ $? != 0 ]
  then
    OK=1
  fi
done

# Install Bundler

gem list -i bundler >/dev/null
if [ $? != 0 ]
then
  echo installing bundler
  gem install bundler --version '< 2'>/dev/null
  if [ $? != 0 ]
  then
    OK=1
  fi
fi
exit $OK

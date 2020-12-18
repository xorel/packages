#!/bin/sh

# ---------------------------------------------------------------------------- #
# Copyright 2020, OpenNebula Project, OpenNebula Systems                       #
#                                                                              #
# Licensed under the Apache License, Version 2.0 (the "License"); you may      #
# not use this file except in compliance with the License. You may obtain      #
# a copy of the License at                                                     #
#                                                                              #
# http://www.apache.org/licenses/LICENSE-2.0                                   #
#                                                                              #
# Unless required by applicable law or agreed to in writing, software          #
# distributed under the License is distributed on an "AS IS" BASIS,            #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.     #
# See the License for the specific language governing permissions and          #
# limitations under the License.                                               #
# ---------------------------------------------------------------------------- #

set -e

# frontend-bootstrap.sh should have bootstrapped the supervisord - if not then
# it either failed and exited (therefore healthcheck is redundant) or it was
# not started at all (e.g.: overidden entrypoint) and then it is irrelevant...

# ...so we wait until supervisord is running:
while sleep 1 ; do
    if [ -f /run/supervisord.pid ] ; then
        _pid=$(cat /run/supervisord.pid)
        if [ -n "$_pid" ] && kill -0 "$_pid" >/dev/null 2>/dev/null ; then
            # supervisord is running -> next step
            break
        fi
    fi
done

# from https://docs.docker.com/engine/reference/builder/:
#   The command’s exit status indicates the health status of the container.
#   The possible values are:
#
#       0: success - the container is healthy and ready for use
#       1: unhealthy - the container is not working correctly
#       2: reserved - do not use this exit code

_status=$(LANG=C supervisorctl status 2>/dev/null | awk '
    {
        if ($2 != "RUNNING") {
            print "1";
            exit 1;
        }
    }
    END {
        print "0";
    }')

if [ "$_status" -eq 0 ] ; then
    exit 0
fi

exit 1

#!/bin/sh

set -e

# give up after two minutes
TIMEOUT=120

#
# functions
#

. /usr/share/one/supervisord/service/functions.sh

#
# dependencies
#

# emulate dependency
echo "OPENNEBULA FLOW: WAIT FOR ONED"
if ! wait_for_oned ; then
    echo "OPENNEBULA FLOW: TIMEOUT"
    exit 1
fi
echo "OPENNEBULA FLOW: ONED IS RUNNING - CONTINUE"

if ! [ -f /var/lib/one/.one/oneflow_auth ] ; then
    echo "OPENNEBULA FLOW: NO ONEFLOW_AUTH"
    exit 1
fi

#
# run service
#

exec /usr/bin/ruby /usr/lib/one/oneflow/oneflow-server.rb

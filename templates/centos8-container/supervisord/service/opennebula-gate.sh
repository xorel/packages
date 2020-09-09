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
echo "OPENNEBULA GATE: WAIT FOR ONED"
if ! wait_for_oned ; then
    echo "OPENNEBULA GATE: TIMEOUT"
    exit 1
fi
echo "OPENNEBULA GATE: ONED IS RUNNING - CONTINUE"

if ! [ -f /var/lib/one/.one/onegate_auth ] ; then
    echo "OPENNEBULA GATE: NO ONEGATE_AUTH"
    exit 1
fi

#
# run service
#

exec /usr/bin/ruby /usr/lib/one/onegate/onegate-server.rb

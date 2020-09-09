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
echo "OPENNEBULA SUNSTONE: WAIT FOR ONED"
if ! wait_for_oned ; then
    echo "OPENNEBULA SUNSTONE: TIMEOUT"
    exit 1
fi
echo "OPENNEBULA SUNSTONE: ONED IS RUNNING - CONTINUE"

if ! [ -f /var/lib/one/.one/sunstone_auth ] ; then
    echo "OPENNEBULA SUNSTONE: NO SUNSTONE_AUTH"
    exit 1
fi

#
# run service
#

exec /usr/bin/ruby /usr/lib/one/sunstone/sunstone-server.rb

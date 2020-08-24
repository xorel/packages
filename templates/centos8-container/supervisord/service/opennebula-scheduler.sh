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
echo "OPENNEBULA SCHEDULER: WAIT FOR ONED"
if ! wait_for_oned ; then
    echo "OPENNEBULA SCHEDULER: TIMEOUT"
    exit 1
fi

if ! [ -f /var/lib/one/.one/one_auth ] ; then
    echo "OPENNEBULA SCHEDULER: NO ONE_AUTH"
    exit 1
fi

#
# run service
#

exec /usr/bin/mm_sched

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
echo "OPENNEBULA SUNSTONE HTTPD: WAIT FOR ONED"
if ! wait_for_oned ; then
    echo "OPENNEBULA SUNSTONE HTTPD: TIMEOUT"
    exit 1
fi
echo "OPENNEBULA SUNSTONE HTTPD: ONED IS RUNNING - CONTINUE"

if ! [ -f /var/lib/one/.one/sunstone_auth ] ; then
    echo "OPENNEBULA SUNSTONE HTTPD: NO SUNSTONE_AUTH"
    exit 1
fi

#
# run service
#

exec /usr/sbin/httpd -c "ErrorLog /dev/stdout" -DFOREGROUND

#!/bin/sh

set -e

# give up after two minutes
TIMEOUT=120

#
# functions
#

. /usr/share/one/supervisord/service/functions.sh

#
# run service
#

# we are talking locally and this pollutes our env.
unset MYSQL_HOST
unset MYSQL_PORT

# wait for mysqld
echo "OPENNEBULA MYSQLD-UPGRADE: WAIT FOR MYSQLD"
if ! wait_for_mysqld ; then
    echo "OPENNEBULA MYSQLD-UPGRADE: TIMEOUT"
    exit 1
fi
echo "OPENNEBULA MYSQLD-UPGRADE: MYSQLD IS RUNNING - CONTINUE"

/usr/libexec/mysql-check-upgrade

# TODO: either this or dealing with a service in EXITED status
exec /bin/sleep infinity

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

/usr/libexec/mysql-check-socket
/usr/libexec/mysql-prepare-db-dir

# emulate ExecStartPost from systemd service unit
for _sv in \
    mysqld-upgrade \
    mysqld-configure \
    ;
do
    if is_running "$_sv" ; then
        supervisorctl stop "$_sv"
    fi
done
# the following postexec services will wait until the pidfile creation
rm -f /var/run/mariadb/mariadb.pid
supervisorctl start mysqld-upgrade
supervisorctl start mysqld-configure

# Note: we set --basedir to prevent probes that might trigger SELinux alarms,
# per bug #547485
exec /usr/libexec/mysqld --basedir=/usr

#!/bin/sh

set -e

# give up after two minutes
TIMEOUT=120

#
# functions
#

. /usr/share/one/supervisord/service/functions.sh

is_root_password_unset()
(
    _check=$(mysql -u root -s -N -e 'select CURRENT_USER();')
    case "$_check" in
        root@*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac

    return 1
)

is_root_password_valid()
(
    _check=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -s -N -e 'select CURRENT_USER();')
    case "$_check" in
        root@*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac

    return 1
)

#
# run service
#

# we are talking locally and this pollutes our env.
unset MYSQL_HOST
unset MYSQL_PORT

# wait for mysqld
echo "OPENNEBULA MYSQLD-CONFIGURE: WAIT FOR MYSQLD"
if ! wait_for_mysqld ; then
    echo "OPENNEBULA MYSQLD-CONFIGURE: TIMEOUT"
    exit 1
fi
echo "OPENNEBULA MYSQLD-CONFIGURE: MYSQLD IS RUNNING - CONTINUE"

# create password, user and database if requested

# root password
if [ -n "$MYSQL_ROOT_PASSWORD" ] ; then
    echo "OPENNEBULA MYSQLD-CONFIGURE: SETUP ROOT PASSWORD"
    if is_root_password_unset ; then
        mysql -u root <<EOF
SET GLOBAL TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET PASSWORD FOR 'root'@'localhost' = PASSWORD('${MYSQL_ROOT_PASSWORD}');
FLUSH PRIVILEGES;
EOF
    else
        if ! is_root_password_valid ; then
            # TODO: support the change of root password?
            echo "MYSQL ROOT PASSWORD WAS ALREADY SET AND DIFFERS - ABORT"
            exit 1
        fi
    fi
fi

# create user and database
if [ -n "$MYSQL_USER" ] \
    && [ -n "$MYSQL_PASSWORD" ] \
    && [ -n "$MYSQL_DATABASE" ] ;
then
    echo "OPENNEBULA MYSQLD-CONFIGURE: SETUP USER AND DATABASE"

    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" <<EOF
CREATE DATABASE IF NOT EXISTS ${MYSQL_DATABASE};
GRANT ALL PRIVILEGES on ${MYSQL_DATABASE}.* to '${MYSQL_USER}'@'%' identified by '${MYSQL_PASSWORD}';
FLUSH PRIVILEGES;
EOF
fi

# secure the mysql installation
echo "OPENNEBULA MYSQLD-CONFIGURE: SECURE THE INSTALLATION"
LANG=C expect -f - <<EOF
set timeout 10
spawn mysql_secure_installation

expect "Enter current password for root (enter for none):"
send "${MYSQL_ROOT_PASSWORD}\n"

expect "Set root password?"
send "n\n"

expect "Remove anonymous users?"
send "Y\n"

expect "Disallow root login remotely?"
send "Y\n"

expect "Remove test database and access to it?"
send "Y\n"

expect "Reload privilege tables now?"
send "Y\n"

expect eof
EOF

# TODO: either this or dealing with a service in EXITED status
exec /bin/sleep infinity

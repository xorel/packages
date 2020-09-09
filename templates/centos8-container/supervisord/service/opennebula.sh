#!/bin/sh

set -e

# give up after two minutes
TIMEOUT=120

#
# functions
#

. /usr/share/one/supervisord/service/functions.sh

wait_for_db()
{
    TIMEOUT="${TIMEOUT:-120}"

    while [ "$TIMEOUT" -gt 0 ] ; do
        if mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -D "$MYSQL_DATABASE" \
            -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" \
            -e 'exit' \
            ;
        then
            return 0
        fi

        TIMEOUT=$(( TIMEOUT - 1 ))
        sleep 1s
    done

    return 1
}

#
# dependencies
#

# emulate dependency
for _requisite in \
    opennebula-ssh-agent \
    ;
do
    if ! is_running "$_requisite" ; then
        supervisorctl start "$_requisite"
    fi
done

#
# run service
#

# wait for mysqld
echo "OPENNEBULA ONED: WAIT FOR DATABASE"
if ! wait_for_db ; then
    echo "OPENNEBULA ONED: TIMEOUT"
    exit 1
fi
echo "OPENNEBULA ONED: DATABASE IS RUNNING - CONTINUE"

for envfile in \
    /var/run/one/ssh-agent.env \
    ;
do
    if [ -f "$envfile" ] ; then
        . "$envfile"
    fi
done

export SSH_AUTH_SOCK

PATH=/usr/lib/one/sh/override:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

exec /usr/bin/oned -f

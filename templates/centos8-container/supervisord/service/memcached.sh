#!/bin/sh

set -e

for envfile in \
    /etc/sysconfig/memcached \
    ;
do
    if [ -f "$envfile" ] ; then
        . "$envfile"
    fi
done

exec /usr/bin/memcached -p ${PORT} -u ${USER} -m ${CACHESIZE} -c ${MAXCONN} $OPTIONS


#!/bin/sh

set -e

for envfile in \
    /etc/crypto-policies/back-ends/opensshserver.config \
    /etc/sysconfig/sshd \
    ;
do
    if [ -f "$envfile" ] ; then
        . "$envfile"
    fi
done

exec /usr/sbin/sshd -D $OPTIONS $CRYPTO_POLICY

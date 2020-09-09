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

# emulate ExecStartPost from systemd service unit
for envfile in \
    /var/run/one/ssh-agent.env \
    ;
do
    if [ -f "$envfile" ] ; then
        . "$envfile"
    fi
done

if [ -z "${SSH_AUTH_SOCK}" ] ; then
    echo "OPENNEBULA SSH-ADD: NO SOCKET ('SSH_AUTH_SOCK')"
    exit 1
fi

export SSH_AUTH_SOCK

# wait for ssh-agent socket
echo "OPENNEBULA SSH-ADD: WAIT FOR SSH-AGENT (${SSH_AUTH_SOCK})"
if ! wait_for_ssh_agent ; then
    echo "OPENNEBULA SSH-ADD: TIMEOUT"
    exit 1
fi
echo "OPENNEBULA SSH-ADD: AGENT IS RUNNING - CONTINUE"

# just in case delete the keys if any found
/usr/bin/ssh-add -D

# add keys
/usr/bin/ssh-add

# TODO: either this or dealing with a service in EXITED status
exec /bin/sleep infinity

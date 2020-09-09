#!/bin/sh

set -e

# give up after two minutes
TIMEOUT=120

#
# functions
#

. /usr/share/one/supervisord/service/functions.sh

check_vnc()
{
    if [ -f /var/lock/one/.novnc.lock ] ; then
        _pid=$(cat /var/lock/one/.novnc.lock)
    else
        return 1
    fi

    if ! kill -0 ${_pid} ; then
        return 1
    fi

    echo "$_pid"

    return 0
}

on_exit()
{
    if _pid=$(check_vnc) ; then
        kill "$_pid"
    fi
}

#
# dependencies
#

# emulate dependency
echo "OPENNEBULA VNC: WAIT FOR ONED"
if ! wait_for_oned ; then
    echo "OPENNEBULA VNC: TIMEOUT"
    exit 1
fi
echo "OPENNEBULA VNC: ONED IS RUNNING - CONTINUE"

#
# run service
#

# NOTE: /usr/bin/novnc-server is daemonizing itself which cannot work with
# supervisord (or runit) and there is no way to switch it to foreground...

# supervisord is managing us - we try to terminate the VNC on exit
trap 'on_exit' INT QUIT TERM EXIT

# start VNC if not running already
if ! _pid=$(check_vnc) ; then
    /usr/bin/novnc-server start
fi

# now we will stay in a loop monitoring and faking the foreground process...
while sleep 1 ; do
    if ! _pid=$(check_vnc) ; then
        echo "OPENNEBULA VNC: VNC-SERVER IS NOT RUNNING"
        exit 1
    fi
done


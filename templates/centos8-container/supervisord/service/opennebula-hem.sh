#!/bin/sh

set -e

#
# functions
#

. /usr/share/one/supervisord/service/functions.sh

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

for envfile in \
    /var/run/one/ssh-agent.env \
    ;
do
    if [ -f "$envfile" ] ; then
        . "$envfile"
    fi
done

export SSH_AUTH_SOCK

exec /usr/bin/ruby /usr/lib/one/onehem/onehem-server.rb

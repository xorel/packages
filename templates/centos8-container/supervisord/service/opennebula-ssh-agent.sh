#!/bin/sh

set -e

SSH_AUTH_SOCK=/var/run/one/ssh-agent.sock
export SSH_AUTH_SOCK

echo "SSH_AUTH_SOCK=${SSH_AUTH_SOCK}" > /var/run/one/ssh-agent.env

# emulate ExecStartPost from systemd service unit
# TODO: instead of /dev/null it would be better to use /dev/stdout but there is
# a permission issue
rm -f "$SSH_AUTH_SOCK"
nohup /bin/sh -c "
    while sleep 1 ; do
        if [ -e ${SSH_AUTH_SOCK} ] ; then
            /usr/bin/ssh-add -D
            /usr/bin/ssh-add
            exit
        fi
    done
" > /dev/null 2>&1 &

exec /usr/bin/ssh-agent -D -a "$SSH_AUTH_SOCK"

#!/bin/sh

set -e

# emulate timer from systemd
while sleep 30 ; do
    /usr/lib/one/sh/ssh-socks-cleaner 2>&1
done


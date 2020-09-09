#!/bin/sh

set -e

# emulate timer from systemd
while sleep 1h ; do
    /usr/bin/oneshowback calculate 2>&1
done


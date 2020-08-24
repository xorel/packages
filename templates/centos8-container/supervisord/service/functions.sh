#!/bin/sh

# here are shared functions for all supervised services

is_running()
(
    _status=$(LANG=C supervisorctl status "$1" | awk '{print $2}')

    case "$_status" in
        RUNNING)
            return 0
            ;;
    esac

    return 1
)

wait_for_oned()
(
    TIMEOUT="${TIMEOUT:-120}"

    while [ "$TIMEOUT" -gt 0 ] ; do
        if oneuser list -x \
           --endpoint "http://${OPENNEBULA_ONED_HOSTNAME}:${OPENNEBULA_ONED_APIPORT}/RPC2" \
           > /dev/null 2>&1 \
           ;
        then
            return 0
        fi

        TIMEOUT=$(( TIMEOUT - 1 ))
        sleep 1
    done

    return 1
)

wait_for_memcached()
(
    TIMEOUT="${TIMEOUT:-120}"

    while [ "$TIMEOUT" -gt 0 ] ; do
        if echo stats | nc "${OPENNEBULA_MEMCACHED_HOSTNAME}" 11211 \
           > /dev/null 2>&1 \
           ;
        then
            return 0
        fi

        TIMEOUT=$(( TIMEOUT - 1 ))
        sleep 1
    done

    return 1
)


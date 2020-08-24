#!/bin/sh

# ---------------------------------------------------------------------------- #
# Copyright 2020, OpenNebula Project, OpenNebula Systems                       #
#                                                                              #
# Licensed under the Apache License, Version 2.0 (the "License"); you may      #
# not use this file except in compliance with the License. You may obtain      #
# a copy of the License at                                                     #
#                                                                              #
# http://www.apache.org/licenses/LICENSE-2.0                                   #
#                                                                              #
# Unless required by applicable law or agreed to in writing, software          #
# distributed under the License is distributed on an "AS IS" BASIS,            #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.     #
# See the License for the specific language governing permissions and          #
# limitations under the License.                                               #
# ---------------------------------------------------------------------------- #

set -e

#
# image params
#

OPENNEBULA_FRONTEND_SERVICE="${OPENNEBULA_FRONTEND_SERVICE:-all}"
OPENNEBULA_FRONTEND_SSH_HOSTNAME="${OPENNEBULA_FRONTEND_SSH_HOSTNAME:-opennebula-frontend}"
OPENNEBULA_ONED_HOSTNAME="${OPENNEBULA_ONED_HOSTNAME:-opennebula-frontend}"
OPENNEBULA_ONED_APIPORT="${OPENNEBULA_ONED_APIPORT:-2633}"
OPENNEBULA_ONEFLOW_HOSTNAME="${OPENNEBULA_ONEFLOW_HOSTNAME:-opennebula-frontend}"
OPENNEBULA_ONEFLOW_APIPORT="${OPENNEBULA_ONEFLOW_APIPORT:-2474}"
OPENNEBULA_ONEGATE_HOSTNAME="${OPENNEBULA_ONEGATE_HOSTNAME:-opennebula-frontend}"
OPENNEBULA_ONEGATE_APIPORT="${OPENNEBULA_ONEGATE_APIPORT:-5030}"
OPENNEBULA_MEMCACHED_HOSTNAME="${OPENNEBULA_MEMCACHED_HOSTNAME:-opennebula-memcached}"
OPENNEBULA_SUNSTONE_HTTPD="${OPENNEBULA_SUNSTONE_HTTPD:-no}"
OPENNEBULA_SUNSTONE_MEMCACHED="${OPENNEBULA_SUNSTONE_MEMCACHED:-no}"
ONEADMIN_USERNAME="${ONEADMIN_USERNAME:-oneadmin}"
#ONEADMIN_PASSWORD
#ONEADMIN_SSH_PRIVKEY
#ONEADMIN_SSH_PUBKEY
MYSQL_HOST="${MYSQL_HOST:-db}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_DATABASE="${MYSQL_DATABASE:-opennebula}"
#MYSQL_PASSWORD
#MYSQL_ROOT_PASSWORD

#
# globals
#

PASSWORD_LENGTH=16

###############################################################################
# functions
#

msg()
{
    echo "[ONEDOCKER]: $*"
}

err()
{
    echo "[ONEDOCKER] [!] ERROR: $*"
}

gen_password()
(
    pw_length="${1:-16}"
    new_pw=''

    while [ "$(echo $new_pw | wc -c)" -lt "$pw_length" ] ; do
        new_pw="${new_pw}$(openssl rand -base64 ${pw_length} | tr -dc '[:alnum:]')"
    done

    echo "$new_pw" | cut -c1-${pw_length}
)

is_true()
(
    _value=$(echo "$1" | tr '[:upper:]' '[:lower:]')

    case "$_value" in
        yes|true|1)
            return 0
            ;;
    esac

    return 1
)

# IMPORTANT!
#
# This is mandatory - before opennebula service is started it needs to have the
# current password of the oneadmin user in ~oneadmin/.one/one_auth. If it is
# the first run then it will be generated.
#
# The issue manifests when the container is restarted - this whole directory
# will be lost. That happens due to the containers being stateless *BUT* if
# this is not the first run then the password is already stored in database and
# we will have possibly newly generated password which will not match the one
# in the database.
#
# For these reasons we need to have a volume:
prepare_oneadmin_data()
{
    # ensure the existence of our auth directory
    if ! [ -d /oneadmin/auth_data/auth ] ; then
        mkdir -p /oneadmin/auth_data/auth
    fi

    # store the password if not already there
    if ! [ -f /oneadmin/auth_data/auth/one_auth ] ; then
        if [ -z "$ONEADMIN_PASSWORD" ] ; then
            msg "GENERATE PASSWORD: NO 'ONEADMIN_PASSWORD'"
            ONEADMIN_PASSWORD=$(gen_password ${PASSWORD_LENGTH})
        fi
        echo "${ONEADMIN_USERNAME}:${ONEADMIN_PASSWORD}" \
            > /oneadmin/auth_data/auth/one_auth
    fi

    # and ensure the correct permissions
    chown "${ONEADMIN_USERNAME}:" /oneadmin
    chown -R "${ONEADMIN_USERNAME}:" /oneadmin/auth_data/auth
    chmod 0700 /oneadmin/auth_data/auth
}

link_oneadmin_auth()
{
    # TODO: can we wait for this prerequisite elsewhere?
    ## ensure the existence of our auth directory
    #if ! [ -d /oneadmin/auth_data/auth ] ; then
    #    err "We need '/oneadmin/auth_data/auth'"
    #    exit 1
    #fi

    # remove .one if not the correct symlink
    if ! [ -L /var/lib/one/.one ] ; then
        rm -rf /var/lib/one/.one
    elif [ "$(readlink /var/lib/one/.one)" != /oneadmin/auth_data/auth ] ; then
        unlink /var/lib/one/.one
    fi

    # symlink oneadmin's auth dir into the volume
    if ! [ -L /var/lib/one/.one ] ; then
        ln -s /oneadmin/auth_data/auth /var/lib/one/.one
    fi
}

link_oneadmin_ssh()
{
    # TODO: can we wait for this prerequisite elsewhere?
    ## ensure the existence of our ssh directory
    #if ! [ -d /oneadmin/ssh_data/ssh ] ; then
    #    err "We need '/oneadmin/ssh_data/ssh'"
    #    exit 1
    #fi

    # remove .ssh if not the correct symlink
    if ! [ -L /var/lib/one/.ssh ] ; then
        rm -rf /var/lib/one/.ssh
    elif [ "$(readlink /var/lib/one/.ssh)" != /oneadmin/ssh_data/ssh ] ; then
        unlink /var/lib/one/.one
    fi

    # symlink oneadmin's ssh config dir into the volume
    if ! [ -L /var/lib/one/.ssh ] ; then
        ln -s /oneadmin/ssh_data/ssh /var/lib/one/.ssh
    fi
}

link_onedata()
{
    # remove datastores if not the correct symlink
    if ! [ -L /var/lib/one/datastores ] ; then
        rm -rf /var/lib/one/datastores
    elif [ "$(readlink /var/lib/one/datastores)" != /data/datastores ] ; then
        unlink /var/lib/one/datastores
    fi

    # symlink datastores into the volume
    if ! [ -L /var/lib/one/datastores ] ; then
        ln -s /data/datastores /var/lib/one/datastores
    fi
}

create_oneadmin_tmpfiles()
{
    systemd-tmpfiles --create /lib/tmpfiles.d/opennebula-common.conf
}

restore_ssh_host_keys()
{
    # create new or restore saved ssh host keys
    if ! [ -d /data/ssh_host_keys ] ; then
        # we have no keys saved
        mkdir -p /data/ssh_host_keys

        # force recreating of new host keys
        rm -f /etc/ssh/ssh_host_*
        ssh-keygen -A

        # save the keys
        cp -a /etc/ssh/ssh_host_* /data/ssh_host_keys/
    else
        # restore the saved ssh host keys
        cp -af /data/ssh_host_keys/ssh_host_* /etc/ssh/
    fi
}

prepare_ssh()
{
    # ensure the existence of ssh directory
    if ! [ -d /oneadmin/ssh_data/ssh ] ; then
        mkdir -p /oneadmin/ssh_data/ssh
    fi

    # if no ssh config is present then use the default
    if ! [ -f /oneadmin/ssh_data/ssh/config ] ; then
        cat /usr/share/one/ssh/config > /oneadmin/ssh_data/ssh/config
        chmod 0644 /oneadmin/ssh_data/ssh/config
    fi

    # copy the custom ssh key-pair
    _private_key_path=
    _public_key_path=
    _custom_key=no
    if [ -n "$ONEADMIN_SSH_PRIVKEY" ] && [ -n "$ONEADMIN_SSH_PUBKEY" ] ; then
        if [ -f "$ONEADMIN_SSH_PRIVKEY" ] && [ -f "$ONEADMIN_SSH_PUBKEY" ] ; then
            _custom_key=yes
            _privkey=$(basename "$ONEADMIN_SSH_PRIVKEY")
            _pubkey=$(basename "$ONEADMIN_SSH_PUBKEY")
            _private_key_path="/oneadmin/ssh_data/ssh/${_privkey}"
            _public_key_path="/oneadmin/ssh_data/ssh/${_pubkey}"

            cat "$ONEADMIN_SSH_PRIVKEY" > "${_private_key_path}"
            chmod 0600 "${_private_key_path}"

            cat "$ONEADMIN_SSH_PUBKEY" > "${_public_key_path}"
            chmod 0644 "${_public_key_path}"

            cat "${_public_key_path}" > /oneadmin/ssh_data/ssh/authorized_keys
            chmod 0644 /oneadmin/ssh_data/ssh/authorized_keys
        fi
    fi

    # generate ssh key-pair if no custom one is provided
    if [ "$_custom_key" != 'yes' ] ; then
        _private_key_path="/oneadmin/ssh_data/ssh/id_rsa"
        _public_key_path="/oneadmin/ssh_data/ssh/id_rsa.pub"

        if ! [ -f "${_private_key_path}" ] || ! [ -f "${_public_key_path}" ] ; then
            rm -f "${_private_key_path}" "${_public_key_path}"
            ssh-keygen -N '' -f "${_private_key_path}"
        fi

        cat "${_public_key_path}" > /oneadmin/ssh_data/ssh/authorized_keys
        chmod 0644 /oneadmin/ssh_data/ssh/authorized_keys
    fi

    chown -R "${ONEADMIN_USERNAME}:" /oneadmin/ssh_data/ssh
    chmod 0700 /oneadmin/ssh_data/ssh

    # store a copy of the authorized_keys and ssh config aside for ssh
    # container to pick it up
    mkdir -p /oneadmin/ssh_pub_data/ssh
    chmod 0700 /oneadmin/ssh_pub_data/ssh
    chown -R "${ONEADMIN_USERNAME}:" /oneadmin/ssh_pub_data/ssh
    if ! [ -f /oneadmin/ssh_pub_data/ssh/authorized_keys ] ; then
        cp -a /oneadmin/ssh_data/ssh/authorized_keys /oneadmin/ssh_pub_data/ssh/
    fi
    if ! [ -f /oneadmin/ssh_pub_data/ssh/config ] ; then
        cp -a /oneadmin/ssh_data/ssh/config /oneadmin/ssh_pub_data/ssh/
    fi

    # TODO: the point of this is to *NOT* have ssh private key here BUT as
    # of now it does not work except when sharing network namespace...
    #
    # Oned fails on deploy because of this command if ssh container does
    # not have access to private ssh key:
    #     scp -r opennebula-frontend-ssh:/var/... node:/var/...
    # in /var/lib/one/remotes/tm/ssh/clone
    #
    # An attempt of simply doing:
    #     echo 127.0.0.1 "$OPENNEBULA_FRONTEND_SSH_HOSTNAME" \
    #       >> /etc/hosts
    #
    # Will not work if sshd is running in separate container and therefore
    # nothing is listening on ssh port in oned container...
    #
    # This is the only workaround for this problem which occurs in all
    # other kinds deployments except when using podman (where all
    # containers connect over localhost and sharing network namespace...)
    _privkey=$(basename "${_private_key_path}")
    if ! [ -f /oneadmin/ssh_pub_data/ssh/${_privkey} ] ; then
        case "$CONTAINER_DEPLOYMENT_TYPE" in
            shared_network_namespace)
                # this works only when network namespace is shared and all
                # containers are binding their ports to localhost
                echo 127.0.0.1 "$OPENNEBULA_FRONTEND_SSH_HOSTNAME" \
                    >> /etc/hosts
                ;;
            *)
                # this absolutely defeats the purpose of having separate sshd
                # container but until opennebula drivers are fixed it is the
                # only fix...
                cp -a "${_private_key_path}" /oneadmin/ssh_pub_data/ssh/
                ;;
        esac
    fi
}

prepare_onedata()
{
    # ensure the existence of the datastores directory
    if ! [ -d /data/datastores ] ; then
        mkdir -p /data/datastores
    fi

    # and ensure the correct permissions
    chown -R "${ONEADMIN_USERNAME}:" /data/datastores
    chmod 0750 /data/datastores
}

configure_oned()
{
    # setup hostname and port
    sed -i \
        -e "s/^[[:space:]#]*HOSTNAME[[:space:]]*=.*/HOSTNAME = \"${OPENNEBULA_FRONTEND_SSH_HOSTNAME}\"/" \
        -e "s/^[[:space:]#]*PORT[[:space:]]*=.*/PORT = \"${OPENNEBULA_ONED_APIPORT}\"/" \
        /etc/one/oned.conf

    # comment-out all DB directives from oned configuration
    #
    # NOTE:
    #   debian/ubuntu uses mawk (1.3.3 Nov 1996) which does not support char.
    #   classes or EREs...
    </etc/one/oned.conf >/etc/one/oned.conf~tmp awk '
    BEGIN {
        state="nil";
    }
    {
        if (state == "nil") {
            if ($0 ~ /^[ ]*DB[ ]*=[ ]*\[/) {
                state = "left-bracket";
                print "# " $0;
            } else if ($0 ~ /^[ ]*DB[ ]*=/) {
                state = "db";
                print "# " $0;
            } else
                print;
        } else if (state == "db") {
            if ($0 ~ /^[ ]*\[/) {
                state = "left-bracket";
                print "# " $0;
            } else
                print "# " $0;
        } else if (state == "left-bracket") {
            if ($0 ~ /[ ]*]/) {
                state = "nil";
                print "# " $0;
            } else
                print "# " $0;
        }
    }
    '
    cat /etc/one/oned.conf~tmp > /etc/one/oned.conf
    rm -f /etc/one/oned.conf~tmp

    # add new DB connections based on the passed env. variables
    cat >> /etc/one/oned.conf <<EOF

#*******************************************************************************
# Custom onedocker configuration
#*******************************************************************************
# This part was dynamically created by the ONE Docker container:
#   opennebula-frontend
#*******************************************************************************

DB = [ backend = "mysql",
       server  = "${MYSQL_HOST}",
       port    = ${MYSQL_PORT},
       user    = "${MYSQL_USER}",
       passwd  = "${MYSQL_PASSWORD}",
       db_name = "${MYSQL_DATABASE}" ]

ONEGATE_ENDPOINT = "http://${OPENNEBULA_ONEGATE_HOSTNAME}:${OPENNEBULA_ONEGATE_APIPORT}"

EOF
}

configure_sunstone()
{
    sed -i \
        -e "s#^:one_xmlrpc:.*#:one_xmlrpc: http://${OPENNEBULA_ONED_HOSTNAME}:${OPENNEBULA_ONED_APIPORT}/RPC2#" \
        -e "s#^:oneflow_server:.*#:oneflow_server: http://${OPENNEBULA_ONEFLOW_HOSTNAME}:${OPENNEBULA_ONEFLOW_APIPORT}#" \
        -e "s#^:tmpdir:.*#:tmpdir: /var/tmp/sunstone/shared#" \
        /etc/one/sunstone-server.conf

    # shared tmpdir with oned
    mkdir -p /var/tmp/sunstone/shared
    chown -R oneadmin:oneadmin /var/tmp/sunstone/shared
    chmod 0755 /var/tmp/sunstone/shared

    # TODO: remove this when sunstone is fixed:
    # https://github.com/OpenNebula/one/issues/5019
    sed -i 's/^\([[:space:]]*webauthn_avail[[:space:]]*\)=.*/\1= false/' \
        /usr/lib/one/sunstone/sunstone-server.rb

    if is_true "${OPENNEBULA_SUNSTONE_HTTPD}" ; then
        mkdir -p /run/passenger
        chown oneadmin:oneadmin /run/passenger
        chmod 0755 /run/passenger

        systemd-tmpfiles --create /lib/tmpfiles.d/passenger.conf

        mkdir -p /run/httpd
        chown root:apache /run/httpd
        chmod 0710 /run/httpd

        # permission settings according to:
        # https://docs.opennebula.io/stable/deployment/sunstone_setup/suns_advance.html
        #chmod a+x /oneadmin/auth_data/auth
        #chgrp apache /var/log/one/sunstone*
        #chmod g+w /var/log/one/sunstone*
        #chgrp apache /etc/one/sunstone-server.conf
        #chown -R root:apache /usr/lib/one/sunstone/public
    fi

    if is_true "${OPENNEBULA_SUNSTONE_MEMCACHED}" ; then
        sed -i \
            -e "s#^:sessions:.*#:sessions: 'memcache'#" \
            -e "s#^:memcache_host:.*#:memcache_host: ${OPENNEBULA_MEMCACHED_HOSTNAME}#" \
            /etc/one/sunstone-server.conf
    fi
}

configure_scheduler()
{
    sed -i \
        -e "s#^ONE_XMLRPC[[:space:]]*=.*#ONE_XMLRPC = \"http://${OPENNEBULA_ONED_HOSTNAME}:${OPENNEBULA_ONED_APIPORT}/RPC2\"#" \
        /etc/one/sched.conf
}

configure_oneflow()
{
    sed -i \
        -e "s#^:one_xmlrpc:.*#:one_xmlrpc: http://${OPENNEBULA_ONED_HOSTNAME}:${OPENNEBULA_ONED_APIPORT}/RPC2#" \
        -e "s#^:host:.*#:host: 0.0.0.0#" \
        -e "s#^:port:.*#:port: ${OPENNEBULA_ONEFLOW_APIPORT}#" \
        /etc/one/oneflow-server.conf
}

configure_onegate()
{
    sed -i \
        -e "s#^:one_xmlrpc:.*#:one_xmlrpc: http://${OPENNEBULA_ONED_HOSTNAME}:${OPENNEBULA_ONED_APIPORT}/RPC2#" \
        -e "s#^:oneflow_server:.*#:oneflow_server: http://${OPENNEBULA_ONEFLOW_HOSTNAME}:${OPENNEBULA_ONEFLOW_APIPORT}#" \
        -e "s#^:host:.*#:host: 0.0.0.0#" \
        -e "s#^:port:.*#:port: ${OPENNEBULA_ONEGATE_APIPORT}#" \
        /etc/one/onegate-server.conf
}

wait_for_mysql()
{
    while ! mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -D "$MYSQL_DATABASE" \
        -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" \
        -e 'exit'
    do
        printf .
        sleep 1s
    done
    echo
}

configure_db()
{
    mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" \
        -u root -p"$MYSQL_ROOT_PASSWORD" \
        -e 'SET GLOBAL TRANSACTION ISOLATION LEVEL READ COMMITTED;'
}

fix_docker()
{
    if ! [ -e /var/run/docker.sock ] ; then
        err "NO DOCKER SOCKET (/var/run/docker.sock): SKIP"
        return 0
    fi

    # save the gid of the docker.sock
    _docker_gid=$(stat -c %g /var/run/docker.sock)

    if getent group | grep -q '^docker:' ; then
        # we reassign the docker's GID to that of the actual docker.sock
        groupmod -g "$_docker_gid" docker
    else
        # we create docker group
        groupadd -r -g "$_docker_gid" docker
    fi

    # and we add oneadmin to the docker group
    gpasswd -a oneadmin docker
}

initialize_supervisord_conf()
{
    # respect the pre-existing config
    _DO_NOT_MODIFY_SUPERVISORD=
    if [ -f /etc/supervisord.conf ] ; then
        _DO_NOT_MODIFY_SUPERVISORD=yes
        return 0
    fi

    # otherwise create an initial stub config
    cp -a /usr/share/one/supervisord/supervisord.conf /etc/supervisord.conf
}

# arg: <service name>
add_supervised_service()
{
    # do not alter the configuration if supervisord.conf was already provided
    if [ -n "$_DO_NOT_MODIFY_SUPERVISORD" ] ; then
        msg "CUSTOM SUPERVISORD.CONF - SKIP: ${1}.ini"
        return 0
    fi

    msg "ADD SUPERVISED SERVICE: /etc/supervisord.d/${1}.ini"
    cp -a "/usr/share/one/supervisord/supervisord.d/${1}.ini" /etc/supervisord.d/
}

common_configuration()
{
    msg "CREATE ONEADMIN's TMPFILES"
    create_oneadmin_tmpfiles

    msg "SYMLINK ONEADMIN's AUTH DATA"
    link_oneadmin_auth

    msg "SYMLINK ONEADMIN's SSH DATA"
    link_oneadmin_ssh

    msg "SYMLINK ONEADMIN's DATASTORES"
    link_onedata
}

#
# frontend services
#

sshd()
{
    msg "PREPARE SSH HOST KEYS"
    restore_ssh_host_keys

    msg "REMOVE NOLOGIN FILES"
    rm -f /etc/nologin /run/nologin

    msg "CREATE ONEADMIN's SSH DIRECTORY"
    mkdir -p /oneadmin/ssh_data/ssh
    chmod 0700 /oneadmin/ssh_data/ssh
    chown -R "${ONEADMIN_USERNAME}:" /oneadmin/ssh_data/ssh

    msg "SETUP SERVICE: SSHD"
    add_supervised_service sshd
}

oned()
{
    msg "FIX DOCKER"
    fix_docker

    msg "PREPARE ONEADMIN's ONE_AUTH"
    prepare_oneadmin_data

    msg "PREPARE ONEADMIN's SSH"
    prepare_ssh

    msg "CONFIGURE DATA"
    prepare_onedata

    msg "CONFIGURE ONED (oned.conf)"
    configure_oned

    msg "WAIT FOR DATABASE"
    wait_for_mysql

    msg "CONFIGURE DATABASE"
    configure_db

    msg "SETUP SERVICE: OPENNEBULA ONED"
    add_supervised_service opennebula
    add_supervised_service opennebula-ssh-agent
    add_supervised_service opennebula-ssh-socks-cleaner
}

sunstone()
{
    msg "CONFIGURE OPENNEBULA SUNSTONE"
    configure_sunstone

    msg "SETUP SERVICE: OPENNEBULA SUNSTONE"
    if is_true "${OPENNEBULA_SUNSTONE_HTTPD}" ; then
        add_supervised_service opennebula-httpd
    else
        add_supervised_service opennebula-sunstone
    fi

    msg "SETUP SERVICE: OPENNEBULA VNC"
    add_supervised_service opennebula-novnc
}

memcached()
{
    msg "SETUP SERVICE: MEMCACHED"
    add_supervised_service memcached
}

scheduler()
{
    msg "CONFIGURE OPENNEBULA SCHEDULER"
    configure_scheduler

    msg "SETUP SERVICE: OPENNEBULA SCHEDULER"
    add_supervised_service opennebula-scheduler
}

oneflow()
{
    msg "CONFIGURE OPENNEBULA FLOW"
    configure_oneflow

    msg "SETUP SERVICE: OPENNEBULA FLOW"
    add_supervised_service opennebula-flow
}

onegate()
{
    msg "CONFIGURE OPENNEBULA GATE"
    configure_onegate

    msg "SETUP SERVICE: OPENNEBULA GATE"
    add_supervised_service opennebula-gate
}

onehem()
{
    # TODO: does it make sense to run separately from oned? (can be even?)
    #msg "CONFIGURE OPENNEBULA HEM"
    #configure_onehem

    msg "SETUP SERVICE: OPENNEBULA HEM"
    add_supervised_service opennebula-hem
}

###############################################################################
# start service
#

# run prestart hook if any
if [ -f /prestart-hook.sh ] && [ -x /prestart-hook.sh ] ; then
    /prestart-hook.sh
fi

msg "BEGIN BOOTSTRAP (${0}): ${OPENNEBULA_FRONTEND_SERVICE}"

# shared steps for all containers
common_configuration
initialize_supervisord_conf

# supervisord needs at least one program section...
msg "SETUP SERVICE: INFINITE LOOP"
add_supervised_service infinite-loop

case "${OPENNEBULA_FRONTEND_SERVICE}" in
    none)
        msg "MAINTENANCE MODE - NO RUNNING SERVICES"
        ;;
    all)
        msg "CONFIGURE FRONTEND SERVICE: ALL"
        sshd
        oned
        scheduler
        oneflow
        onegate
        onehem
        sunstone
        # note: memcached is not used by default
        ;;
    oned)
        msg "CONFIGURE FRONTEND SERVICE: ONED"
        oned
        onehem
        ;;
    sshd)
        msg "CONFIGURE FRONTEND SERVICE: SSHD"
        sshd
        ;;
    memcached)
        msg "CONFIGURE FRONTEND SERVICE: MEMCACHED"
        memcached
        ;;
    sunstone)
        msg "CONFIGURE FRONTEND SERVICE: SUNSTONE"
        sunstone
        ;;
    scheduler)
        msg "CONFIGURE FRONTEND SERVICE: SCHEDULER"
        scheduler
        ;;
    oneflow)
        msg "CONFIGURE FRONTEND SERVICE: ONEFLOW"
        oneflow
        ;;
    onegate)
        msg "CONFIGURE FRONTEND SERVICE: ONEGATE"
        onegate
        ;;
    *)
        err "UNKNOWN FRONTEND SERVICE: ${OPENNEBULA_FRONTEND_SERVICE}"
        exit 1
        ;;
esac

msg "BOOTSTRAP FINISHED"

msg "EXEC SUPERVISORD"
exec /usr/bin/supervisord -n -c /etc/supervisord.conf


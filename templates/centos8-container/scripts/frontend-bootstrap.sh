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

# frontend

export OPENNEBULA_FRONTEND_SERVICE="${OPENNEBULA_FRONTEND_SERVICE:-all}"
export OPENNEBULA_FRONTEND_HOST
export OPENNEBULA_FRONTEND_SSH_HOST="${OPENNEBULA_FRONTEND_SSH_HOST:-${OPENNEBULA_FRONTEND_HOST}}"
export OPENNEBULA_FRONTEND_PREHOOK
export OPENNEBULA_FRONTEND_POSTHOOK
export OPENNEBULA_FRONTEND_ONECFG_PATCH
export MAINTENANCE_MODE="${MAINTENANCE_MODE:-no}"

# oned

export ONED_HOST="${ONED_HOST:-localhost}"
export ONED_INTERNAL_PORT=2633
export ONED_INTERNAL_TLS_PORT=2634
export ONED_DB_BACKUP_ENABLED="${ONED_DB_BACKUP_ENABLED:-yes}"

# oneflow

export ONEFLOW_HOST="${ONEFLOW_HOST:-localhost}"
export ONEFLOW_INTERNAL_PORT=2474
export ONEFLOW_INTERNAL_TLS_PORT=2475

# onegate

export ONEGATE_HOST="${ONEGATE_HOST:-localhost}"
export ONEGATE_INTERNAL_PORT=5030
export ONEGATE_INTERNAL_TLS_PORT=5031
# NOTE: this is needed so the oned can advertise this port
export ONEGATE_PORT="${ONEGATE_PORT:-5030}"

# memcached

export MEMCACHED_HOST="${MEMCACHED_HOST:-localhost}"
export MEMCACHED_INTERNAL_PORT=11211

# oneprovision

export ONEPROVISION_HOST="${ONEPROVISION_HOST:-localhost}"
export ONEPROVISION_PORT=2222

# guacd

export GUACD_HOST="${GUACD_HOST:-localhost}"
export GUACD_INTERNAL_PORT=4822

# fireedge

export FIREEDGE_HOST="${FIREEDGE_HOST:-localhost}"
export FIREEDGE_INTERNAL_PORT=2616

# sunstone

export SUNSTONE_INTERNAL_PORT=80
export SUNSTONE_INTERNAL_TLS_PORT=443
# NOTE: this is not ideal - but I need to match and/or redirect these ports...
export SUNSTONE_PORT="${SUNSTONE_PORT:-80}"
export SUNSTONE_TLS_PORT="${SUNSTONE_TLS_PORT:-443}"
# TODO: can this be just internal port - is this proxied or advertised?
export SUNSTONE_VNC_PORT="${SUNSTONE_VNC_PORT:-29876}"
# NOTE: HTTP redirection is no longer optional (it will be set to yes when HTTPS is enabled)
export SUNSTONE_HTTP_REDIRECT=no
export SUNSTONE_HTTPS_ENABLED="${SUNSTONE_HTTPS_ENABLED:-yes}"

# TLS

export TLS_PROXY_ENABLED="${TLS_PROXY_ENABLED:-no}"
export TLS_DOMAIN_LIST="${TLS_DOMAIN_LIST:-*}"
export TLS_VALID_DAYS="${TLS_VALID_DAYS:-365}"
export TLS_CERT_BASE64
export TLS_KEY_BASE64
export TLS_CERT
export TLS_KEY

# docker

# docker needs to run in privileged container - therefore disabled by default
export DIND_ENABLED="${DIND_ENABLED:-no}"
export DIND_HOST="${DIND_HOST:-localhost}"
export DIND_INTERNAL_PORT=2375
export DIND_SOCKET="${DIND_SOCKET:-/var/run/docker.sock}"
export DIND_TCP_ENABLED="${DIND_TCP_ENABLED:-no}"

# oneadmin

# TODO: oneadmin is hardcoded on the installation - a change here would only broke things
#export ONEADMIN_USERNAME="${ONEADMIN_USERNAME:-oneadmin}"
export ONEADMIN_USERNAME="oneadmin"
export ONEADMIN_PASSWORD
export ONEADMIN_SSH_PRIVKEY="${ONEADMIN_SSH_PRIVKEY:-/ssh/id_rsa}"
export ONEADMIN_SSH_PUBKEY="${ONEADMIN_SSH_PUBKEY:-/ssh/id_rsa.pub}"
export ONEADMIN_SSH_PRIVKEY_BASE64
export ONEADMIN_SSH_PUBKEY_BASE64

# mysql

export MYSQL_HOST="${MYSQL_HOST:-localhost}"
export MYSQL_PORT="${MYSQL_PORT:-3306}"
export MYSQL_DATABASE="${MYSQL_DATABASE:-opennebula}"
export MYSQL_USER="${MYSQL_USER:-oneadmin}"
export MYSQL_PASSWORD
export MYSQL_ROOT_PASSWORD

#
# globals
#

PASSWORD_LENGTH=16
DELETE_LIST="/var/tmp/delete_on_bootstrap_exit"
TIMEOUT=120 # in seconds

###############################################################################
# functions
#

msg()
{
    printf "$(date '+%F %T') [BOOTSTRAP] $(hostname): $*\n"
}

err()
{
    printf "$(date '+%F %T') [BOOTSTRAP] $(hostname) [!] ERROR: $*\n"
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

on_exit()
{
    exit_status=$?

    # delete locks and temp files
    if [ -f "$DELETE_LIST" ] ; then
        cat "$DELETE_LIST" | while read -r _filename ; do
            rm -rf "$_filename"
        done
    fi

    # unset signal handlers to avoid exiting once more
    trap '' EXIT INT QUIT TERM
    exit $exit_status
}

sig_exit()
{
    # workaround for different behaviors in different shells
    trap '' EXIT

    false # set faulty exit status

    # and exit
    on_exit
}

# Feed augtool commands on stdin of this function:
#
# this will make augtool little faster by using only needed lenses and executing
# commands in one run
#
# Example:
#
# % augtool_helper /etc/one/oned.conf <<EOF
# > set HOSTNAME '"${OPENNEBULA_FRONTEND_SSH_HOST}"'
# > set PORT '"${ONED_INTERNAL_PORT}"'
# > EOF
# %
#
# args: <absolute-path-to-the-edited-file>
augtool_helper()
{
    augtool --noload --interactive <<EOF
rm /augeas/load/*["${1}"!~glob(incl) or "${1}"=~glob(excl)]
load
set /augeas/context /files${1}
$(cat)
save
quit
EOF
}

# Analogical to the augtool_helper usage but for onecfg command:
#
# deduplicate filename and provide some boilerplate
#
# args: <absolute-path-to-the-edited-file>
onecfg_helper()
{
    # output is surpressed because it is not good idea to have passwords in the
    # log...
    #
    # also due to the result code not being always zero when not all changes
    # are applied - we wrap the command in the if-else construct
    if ! sed "s#.*#${1} &#" | onecfg patch --format line >/dev/null 2>&1 ; then
        if [ $? -ne 1 ] ; then
            err "ONECFG: Patching the file '${1}' failed - ABORT"
            exit 1
        fi
    fi
}

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
prepare_oneadmin_auth()
{
    # ensure the existence of our auth directory
    if ! [ -d /var/lib/one/.one ] ; then
        mkdir -p /var/lib/one/.one
    fi

    # store the password if not already there
    if ! [ -f /var/lib/one/.one/one_auth ] ; then
        if [ -z "$ONEADMIN_PASSWORD" ] ; then
            msg "ONEADMIN: Empty 'ONEADMIN_PASSWORD' - generate random"
            ONEADMIN_PASSWORD=$(gen_password ${PASSWORD_LENGTH})
        fi
        echo "${ONEADMIN_USERNAME}:${ONEADMIN_PASSWORD}" \
            > /var/lib/one/.one/one_auth
    fi

    # and ensure the correct permissions
    chown -R "${ONEADMIN_USERNAME}:" /var/lib/one/.one
    chmod 0700 /var/lib/one/.one
}

create_common_tmpfiles()
{
    systemd-tmpfiles --create \
        /lib/tmpfiles.d/etc.conf \
        /lib/tmpfiles.d/dbus.conf \
        /lib/tmpfiles.d/legacy.conf \
        /lib/tmpfiles.d/pam.conf \
        /lib/tmpfiles.d/sudo.conf \
        /lib/tmpfiles.d/supervisor.conf \
        /lib/tmpfiles.d/var.conf \
        ;
}

create_ssh_tmpfiles()
{
    systemd-tmpfiles --create /lib/tmpfiles.d/openssh.conf
}

create_oneadmin_tmpfiles()
{
    systemd-tmpfiles --create /lib/tmpfiles.d/opennebula-common.conf
}

create_httpd_tmpfiles()
{
    systemd-tmpfiles --create /lib/tmpfiles.d/httpd.conf
    systemd-tmpfiles --create /lib/tmpfiles.d/passenger.conf
}

create_mariadb_tmpfiles()
{
    systemd-tmpfiles --create /lib/tmpfiles.d/mariadb.conf
}

restore_ssh_host_keys()
{
    _ssh_host_key_lock=/srv/one/secret-ssh-host-keys/ssh-keygen.lock
    _ssh_host_privkey=/etc/ssh/ssh_host_rsa_key
    _ssh_host_pubkey=/etc/ssh/ssh_host_rsa_key.pub

    msg "SSHD: Lock or wait for ssh host keys"
    if ! lock_or_skip "$_ssh_host_key_lock" ; then
        msg "SSHD: Failed to acquire lock: waiting (${TIMEOUT} secs)..."

        if ! wait_for_file "$_ssh_host_privkey" ; then
            err "SSHD: Reached timeout: no ssh host key (${_ssh_host_privkey}) - ABORT"
            exit 1
        fi

        if ! wait_for_file "$_ssh_host_pubkey" ; then
            err "SSHD: reached timeout: no ssh host key (${_ssh_host_pubkey}) - ABORT"
            exit 1
        fi

        msg "SSHD: Success - file emerged"
        return 0
    fi

    msg "SSHD: Acquired lock for ssh host key manipulation"

    # create new or restore saved ssh host keys
    _ssh_keys=$(ls -1 \
        /srv/one/secret-ssh-host-keys/ssh_host_* \
        2>/dev/null | wc -l)
    if [ "$_ssh_keys" -eq 0 ] ; then
        # we have no keys saved
        msg "SSHD: Generate new ssh host keys"

        # force recreating of new host keys
        rm -f /etc/ssh/ssh_host_*
        ssh-keygen -A

        # save the keys
        cp -p /etc/ssh/ssh_host_* /srv/one/secret-ssh-host-keys/
    else
        # restore the saved ssh host keys
        msg "SSHD: Restore existing ssh host keys"

        rm -f /etc/ssh/ssh_host_*
        cp -p /srv/one/secret-ssh-host-keys/ssh_host_* /etc/ssh/
    fi

    # cleanup the temp files
    remove_lock "$_ssh_host_key_lock"
}

# arg: [<ssh dir>]
generate_ssh_key()
(
    _ssh_dir="${1:-/var/lib/one/.ssh}"

    # ensure the existence of ssh directory
    if ! [ -d "${_ssh_dir}" ] ; then
        mkdir -p "${_ssh_dir}"
    fi

    # generate ssh key-pair once
    _private_key_path="${_ssh_dir}/id_rsa"
    _public_key_path="${_ssh_dir}/id_rsa.pub"

    if ! [ -f "${_private_key_path}" ] || ! [ -f "${_public_key_path}" ] ; then
        rm -f "${_private_key_path}" "${_public_key_path}"
        ssh-keygen -N '' -f "${_private_key_path}"
    fi

    cat "${_public_key_path}" > "${_ssh_dir}/authorized_keys"
    chmod 0644 "${_ssh_dir}/authorized_keys"
)

prepare_ssh()
{
    # ensure the existence of ssh directory
    if ! [ -d /var/lib/one/.ssh ] ; then
        mkdir -p /var/lib/one/.ssh
    fi

    # copy the custom ssh key-pair
    _private_key_path=
    _public_key_path=
    _custom_key=no
    if [ -n "$ONEADMIN_SSH_PRIVKEY_BASE64" ] && [ -n "$ONEADMIN_SSH_PUBKEY_BASE64" ] ; then
        _custom_cert=yes
        _private_key_path="/var/lib/one/.ssh/id_rsa"
        _public_key_path="/var/lib/one/.ssh/id_rsa.pub"

        if ! echo "$ONEADMIN_SSH_PRIVKEY_BASE64" | base64 -d > "${_private_key_path}.tmp" ; then
            err "'ONEADMIN_SSH_PRIVKEY_BASE64' does not have a base64 value - ABORT"
            exit 1
        fi
        mv "${_private_key_path}.tmp" "${_private_key_path}"
        chmod 0600 "${_private_key_path}"

        if ! echo "$ONEADMIN_SSH_PUBKEY_BASE64" | base64 -d > "${_public_key_path}.tmp" ; then
            err "'ONEADMIN_SSH_PUBKEY_BASE64' does not have a base64 value - ABORT"
            exit 1
        fi
        mv "${_public_key_path}.tmp" "${_public_key_path}"
        chmod 0644 "${_public_key_path}"
    elif [ -n "$ONEADMIN_SSH_PRIVKEY" ] && [ -n "$ONEADMIN_SSH_PUBKEY" ] ; then
        if [ -f "$ONEADMIN_SSH_PRIVKEY" ] && [ -f "$ONEADMIN_SSH_PUBKEY" ] ; then
            _custom_key=yes
            _privkey=$(basename "$ONEADMIN_SSH_PRIVKEY")
            _pubkey=$(basename "$ONEADMIN_SSH_PUBKEY")
            _private_key_path="/var/lib/one/.ssh/${_privkey}"
            _public_key_path="/var/lib/one/.ssh/${_pubkey}"

            cat "$ONEADMIN_SSH_PRIVKEY" > "${_private_key_path}"
            chmod 0600 "${_private_key_path}"

            cat "$ONEADMIN_SSH_PUBKEY" > "${_public_key_path}"
            chmod 0644 "${_public_key_path}"

            cat "${_public_key_path}" > /var/lib/one/.ssh/authorized_keys
            chmod 0644 /var/lib/one/.ssh/authorized_keys
        fi
    fi

    # generate ssh key-pair if no custom one is provided
    if [ "$_custom_key" != 'yes' ] ; then
        generate_ssh_key
    fi

    # if no ssh config is present then use the default
    if ! [ -f /var/lib/one/.ssh/config ] ; then
        cat /usr/share/one/ssh/config > /var/lib/one/.ssh/config
        chmod 0600 /var/lib/one/.ssh/config
    fi

    # set ownership/permissions
    chown -R "${ONEADMIN_USERNAME}:" /var/lib/one/.ssh
    chmod 0700 /var/lib/one/.ssh

    # store a copy of the authorized_keys and ssh config aside for ssh
    # container to pick it up

    mkdir -p /var/lib/one/.ssh-copyback
    chmod 0700 /var/lib/one/.ssh-copyback
    chown -R "${ONEADMIN_USERNAME}:" /var/lib/one/.ssh-copyback

    if ! [ -f /var/lib/one/.ssh-copyback/authorized_keys ] ; then
        cp -a /var/lib/one/.ssh/authorized_keys /var/lib/one/.ssh-copyback/
    fi

    if ! [ -f /var/lib/one/.ssh-copyback/config ] ; then
        cp -a /var/lib/one/.ssh/config /var/lib/one/.ssh-copyback/
    fi
}

prepare_ssh_oneadmin_provision()
{
    # generate ssh key-pair once
    generate_ssh_key

    # restrict commands to oneprovision* and oneprovider only
    _ssh_command='command="/usr/local/bin/oneprovision.sh $SSH_ORIGINAL_COMMAND",no-port-forwarding,no-x11-forwarding,no-agent-forwarding'
    sed -i "s#.*#${_ssh_command} &#" /var/lib/one/.ssh/authorized_keys

    # if no ssh config is present then use the default
    if ! [ -f /var/lib/one/.ssh/config ] ; then
        cat /usr/share/one/ssh/config > /var/lib/one/.ssh/config
        chmod 0600 /var/lib/one/.ssh/config
    fi

    # set ownership/permissions
    chown -R "${ONEADMIN_USERNAME}:" /var/lib/one/.ssh
    chmod 0700 /var/lib/one/.ssh
}

prepare_ssh_oneprovision()
{
    # generate ssh key-pair once
    generate_ssh_key /var/lib/one/.ssh-oneprovision
    rm -f /var/lib/one/.ssh-oneprovision/authorized_keys

    # set ownership/permissions
    chown -R "${ONEADMIN_USERNAME}:" /var/lib/one/.ssh-oneprovision
    chmod 0700 /var/lib/one/.ssh-oneprovision
}

# arg: <lockfile>
lock_or_skip()
(
    _lock_file="$1"
    _tmp_file=$(mktemp "${1}-XXXX")

    # no need to store pid because the process would not be seen from other
    # container anyway...so we store our own name to be deleted later
    echo "$_tmp_file" > "$_tmp_file"

    # store filenames in the file for potential cleanup on an abrupt exit
    echo "$_tmp_file" >> "$DELETE_LIST"
    echo "$_lock_file" >> "$DELETE_LIST"

    # hardlink is atomic operation
    if ! ln "$_tmp_file" "$_lock_file" >/dev/null 2>&1 ; then
        # lock already exists
        rm -f "$_tmp_file"
        return 1
    fi

    # delete temp file - lock file is hardlink so it stays
    rm -f "$_tmp_file"

    return 0
)

# arg: <lockfile>
remove_lock()
(
    _lock_file="$1"
    _tmp_file=$(cat "$_lock_file")

    rm -f "$_lock_file" "$_tmp_file"
)

execute_delete_list()
(
    cat "${DELETE_LIST}" | while read -r filename ; do
        rm -rf "${filename}"
    done

    rm -f "${DELETE_LIST}"
)

wait_for_file()
(
    TIMEOUT="${TIMEOUT:-120}"

    while [ "$TIMEOUT" -gt 0 ] ; do
        if [ -e "$1" ] ; then
            return 0
        fi

        TIMEOUT=$(( TIMEOUT - 1 ))
        sleep 1
    done

    return 1
)

prepare_cert()
(
    # internal filepaths can be hardcoded - only the content varies
    _cert_path="/srv/one/secret-tls/one.crt"
    _key_path="/srv/one/secret-tls/one.key"
    _cert_conf_path="/srv/one/secret-tls/one.conf"
    _cert_lock="/srv/one/secret-tls/one.lock"

    # ensure the existence of cert directory
    if ! [ -d /srv/one/secret-tls ] ; then
        mkdir -p /srv/one/secret-tls
    fi

    msg "CERTIFICATE: Lock or wait for TLS certificate"
    if ! lock_or_skip "$_cert_lock" ; then
        msg "CERTIFICATE: Failed to acquire lock: waiting (${TIMEOUT} secs)..."

        if ! wait_for_file "$_cert_path" ; then
            err "CERTIFICATE: reached timeout - ABORT"
            exit 1
        fi

        if ! wait_for_file "$_key_path" ; then
            err "CERTIFICATE: reached timeout - ABORT"
            exit 1
        fi

        msg "CERTIFICATE: Success - file emerged"
        return 0
    fi

    msg "CERTIFICATE: Acquired lock for certificate manipulation"

    # copy the custom certificate
    _custom_cert=no
    if [ -n "$TLS_CERT_BASE64" ] && [ -n "$TLS_KEY_BASE64" ] ; then
        _custom_cert=yes

        if ! echo "$TLS_KEY_BASE64" | base64 -d > "${_key_path}.tmp" ; then
            err "CERTIFICATE: 'TLS_KEY_BASE64' does not have a base64 value - ABORT"
            return 1
        fi
        mv "${_key_path}.tmp" "${_key_path}"
        chmod 0600 "${_key_path}"

        if ! echo "$TLS_CERT_BASE64" | base64 -d > "${_cert_path}.tmp" ; then
            err "CERTIFICATE: 'TLS_CERT_BASE64' does not have a base64 value - ABORT"
            return 1
        fi
        mv "${_cert_path}.tmp" "${_cert_path}"
        chmod 0644 "${_cert_path}"
    elif [ -n "$TLS_CERT" ] && [ -n "$TLS_KEY" ] ; then
        if [ -f "$TLS_CERT" ] && [ -f "$TLS_KEY" ] ; then
            _custom_cert=yes

            cat "$TLS_CERT" > "${_cert_path}"
            chmod 0644 "${_cert_path}"

            cat "$TLS_KEY" > "${_key_path}"
            chmod 0600 "${_key_path}"
        fi
    fi

    # generate self-signed certificate if no custom one is provided
    if [ "$_custom_cert" != 'yes' ] ; then
        # Compose the domain list:
        #
        # we either use a user provided domain list or we will default the
        # TLS_DOMAIN_LIST to the asterisk ('*') which is defined at the top of
        # this bootstrap script - in the image params section

        # exploit the shell argument array
        set -f
        set -- ${TLS_DOMAIN_LIST}
        set +f
        _cn="${1}"
        shift

        # loop over the rest of the names to create a valid list prefixed
        # with 'DNS:' to be used as a value for subjectAltName
        _alt=
        for _name in $* ; do
            _alt="${_alt}${_alt:+,} DNS:${_name}"
        done

        # this config serves as a initial starting point for a robust TLS
        # certificate creation - feel free to introduce more image params and
        # uncomment some other attributes below...
        cat > "${_cert_conf_path}.new" <<EOF
# IMPORTANT: THIS FILE IS AUTOGENERATED - PLEASE DO NOT EDIT !

# There is no way how to define valid days inside the openssl config therefore
# we at least leave it in the comments so we can compare the changes...
#
# VALID DAYS = ${TLS_VALID_DAYS}

[ req ]
prompt             = no
default_bits       = 4096
distinguished_name = req_distinguished_name
req_extensions     = req_ext

[ req_distinguished_name ]
#countryName                       = Country Name (2 letter code)
#countryName_default               = AU
#countryName_min                   = 2
#countryName_max                   = 2

#stateOrProvinceName               = State or Province Name (full name)
#stateOrProvinceName_default       = Some-State

#localityName                      = Locality Name (eg, city)

#0.organizationName                = Organization Name (eg, company)
#0.organizationName_default        = Internet Widgits Pty Ltd

#1.organizationName                = Second Organization Name (eg, company)
#1.organizationName_default        = World Wide Web Pty Ltd

#organizationalUnitName            = Organizational Unit Name (eg, section)
#organizationalUnitName_default    =

commonName                        = ${_cn}
#commonName_max                    = 64

#emailAddress                      = Email Address
#emailAddress_max                  = 40

[ req_ext ]
$(if [ -n "${_alt}" ] ; then
    echo "subjectAltName                    = ${_alt}" ;
fi;)

EOF

        # if we already created a cert and the cert params are unchanged then
        # we do not wish to generate a new one...
        if [ -f "${_cert_path}" ] && [ -f "${_key_path}" ] ; then
            # compare the new openssl config with the old one if it exists and
            # if they differ then regenerate the cert...

            # compare the newly generated config with the old one
            if [ -f "${_cert_conf_path}" ] ; then
                _new_cert_conf_hash=$(sha256sum < "${_cert_conf_path}.new")
                _old_cert_conf_hash=$(sha256sum < "${_cert_conf_path}")

                if [ "${_new_cert_conf_hash}" = "${_old_cert_conf_hash}" ] ; then
                    # the cert does not need to be generated again
                    msg "CERTIFICATE: Found existing certificate"
                    rm -f "${_cert_conf_path}.new"
                    remove_lock "$_cert_lock"
                    return 0
                fi
            fi
        fi

        # store the new openssl config
        mv "${_cert_conf_path}.new" "${_cert_conf_path}"

        # we remove the leftover old cert in the internal path
        rm -f "${_cert_path}" "${_key_path}"

        msg "CERTIFICATE: Generate new"
        openssl req -new -x509 -sha256 -nodes -batch \
            -config "${_cert_conf_path}" \
            -extensions req_ext \
            -days "${TLS_VALID_DAYS}" \
            -out "${_cert_path}" \
            -keyout "${_key_path}"
    fi

    # cleanup the temp files
    remove_lock "$_cert_lock"

    chown -R "${ONEADMIN_USERNAME}:" /srv/one/secret-tls
    chmod 0700 /srv/one/secret-tls
)

configure_tlsproxy()
(
    _name=
    _accept_port=
    _connect_port=

    case "$1" in
        oned)
            _name="$1"
            _accept_port="${ONED_INTERNAL_TLS_PORT}"
            _connect_port="${ONED_INTERNAL_PORT}"
            ;;
        onegate)
            _name="$1"
            _accept_port="${ONEGATE_INTERNAL_TLS_PORT}"
            _connect_port="${ONEGATE_INTERNAL_PORT}"
            ;;
        oneflow)
            _name="$1"
            _accept_port="${ONEFLOW_INTERNAL_TLS_PORT}"
            _connect_port="${ONEFLOW_INTERNAL_PORT}"
            ;;
        *)
            err "STUNNEL: Unknown TLS proxy service '${1}' - ABORT"
            exit 1
            ;;
    esac

    if [ -f /srv/one/secret-tls/one.crt ] && [ -f /srv/one/secret-tls/one.key ] ; then
        cat > "/etc/stunnel/conf.d/${_name}.conf" <<EOF
[${_name}]
accept = ${_accept_port}
connect = ${_connect_port}
cert = /srv/one/secret-tls/one.crt
key = /srv/one/secret-tls/one.key
EOF
    else
        err "STUNNEL: TLS proxy requested but no certs provided - ABORT"
        exit 1
    fi
)

configure_oned()
{
    # setup hostname and port
    onecfg_helper /etc/one/oned.conf <<EOF
set HOSTNAME "\"${OPENNEBULA_FRONTEND_SSH_HOST}\""
set PORT ${ONED_INTERNAL_PORT}
EOF

    # add new DB connections based on the passed env. variables
    onecfg_helper /etc/one/oned.conf <<EOF
set DB/BACKEND "\"mysql\""
set DB/SERVER  "\"${MYSQL_HOST}\""
set DB/PORT    ${MYSQL_PORT}
set DB/USER    "\"${MYSQL_USER}\""
set DB/PASSWD  "\"${MYSQL_PASSWORD}\""
set DB/DB_NAME "\"${MYSQL_DATABASE}\""
EOF

    # advertise this onegate endpoint
    if is_true "${TLS_PROXY_ENABLED}" ; then
        onecfg_helper /etc/one/oned.conf <<EOF
set ONEGATE_ENDPOINT "\"https://${OPENNEBULA_FRONTEND_HOST}:${ONEGATE_PORT}\""
EOF
    else
        onecfg_helper /etc/one/oned.conf <<EOF
set ONEGATE_ENDPOINT "\"http://${OPENNEBULA_FRONTEND_HOST}:${ONEGATE_PORT}\""
EOF
    fi

    # populate service env file
    cat > /etc/default/supervisor/oned <<EOF
export MYSQL_HOST="${MYSQL_HOST}"
export MYSQL_PORT="${MYSQL_PORT}"
export MYSQL_DATABASE="${MYSQL_DATABASE}"
export MYSQL_USER="${MYSQL_USER}"
export MYSQL_PASSWORD="${MYSQL_PASSWORD}"
export ONED_DB_BACKUP_ENABLED="${ONED_DB_BACKUP_ENABLED}"
EOF
}

configure_sunstone()
{
    onecfg_helper /etc/one/sunstone-server.conf <<EOF
SET :one_xmlrpc "http://${ONED_HOST}:${ONED_INTERNAL_PORT}/RPC2"
SET :oneflow_server "http://${ONEFLOW_HOST}:${ONEFLOW_INTERNAL_PORT}"
SET :port ${SUNSTONE_INTERNAL_PORT}
SET :vnc_proxy_port ${SUNSTONE_VNC_PORT}
SET :tmpdir "/var/tmp/sunstone/shared"
SET :private_fireedge_endpoint "http://${FIREEDGE_HOST}:${FIREEDGE_INTERNAL_PORT}"
EOF

    # this will decide where sunstone will point client to fireedge
    if is_true "${SUNSTONE_HTTPS_ENABLED}" ; then
        onecfg_helper /etc/one/sunstone-server.conf <<EOF
SET :public_fireedge_endpoint "https://${OPENNEBULA_FRONTEND_HOST}:${SUNSTONE_TLS_PORT}"
EOF
    else
        onecfg_helper /etc/one/sunstone-server.conf <<EOF
SET :public_fireedge_endpoint "http://${OPENNEBULA_FRONTEND_HOST}:${SUNSTONE_PORT}"
EOF
    fi

    # enable vnc over ssl when https is required and certs provided
    if is_true "${SUNSTONE_HTTPS_ENABLED}" ; then
        # value can be: no, yes, only
        _wss="only"

        onecfg_helper /etc/one/sunstone-server.conf <<EOF
SET :vnc_proxy_support_wss "${_wss}"
SET :vnc_proxy_cert "/srv/one/secret-tls/one.crt"
SET :vnc_proxy_key "/srv/one/secret-tls/one.key"
EOF
    fi

    # shared tmpdir with oned
    mkdir -p /var/tmp/sunstone/shared
    chown -R oneadmin:oneadmin /var/tmp/sunstone/shared
    chmod 0755 /var/tmp/sunstone/shared

    # shared vmrc_tokens with fireedge
    mkdir -p /var/lib/one/sunstone_vmrc_tokens
    chown -R oneadmin:oneadmin /var/lib/one/sunstone_vmrc_tokens
    chmod 0755 /var/lib/one/sunstone_vmrc_tokens

    # setup apache if requested
    mkdir -p /run/passenger
    chown oneadmin:oneadmin /run/passenger
    chmod 0755 /run/passenger

    systemd-tmpfiles --create /lib/tmpfiles.d/passenger.conf

    mkdir -p /run/httpd
    chown root:apache /run/httpd
    chmod 0710 /run/httpd

    # enable HTTP VirtualHost
    #
    # NOTE: due to other dependencies HTTP must be always enabled and if
    # HTTPS is enabled then HTTP redirection is mandatory
    cp -a /etc/httpd/conf.d/opennebula-http.conf-disabled \
        /etc/httpd/conf.d/opennebula-http.conf

    # enable HTTPS VirtualHost
    if is_true "${SUNSTONE_HTTPS_ENABLED}" ; then
        # the if conditional in the httpd conf will expect yes or true
        SUNSTONE_HTTP_REDIRECT='yes'

        cp -a /etc/httpd/conf.d/opennebula-https.conf-disabled \
            /etc/httpd/conf.d/opennebula-https.conf
    fi

    # configure memcached
    onecfg_helper /etc/one/sunstone-server.conf <<EOF
SET :sessions "memcache"
SET :memcache_host "${MEMCACHED_HOST}"
SET :memcache_port ${MEMCACHED_INTERNAL_PORT}
EOF

    # populate service env file
    cat > /etc/default/supervisor/sunstone <<EOF
export SUNSTONE_HTTP_REDIRECT="${SUNSTONE_HTTP_REDIRECT}"
export SUNSTONE_INTERNAL_PORT="${SUNSTONE_INTERNAL_PORT}"
export SUNSTONE_INTERNAL_TLS_PORT="${SUNSTONE_INTERNAL_TLS_PORT}"
export SUNSTONE_PORT="${SUNSTONE_PORT}"
export SUNSTONE_TLS_PORT="${SUNSTONE_TLS_PORT}"
export FIREEDGE_HOST="${FIREEDGE_HOST}"
export FIREEDGE_INTERNAL_PORT="${FIREEDGE_INTERNAL_PORT}"
EOF
}

configure_memcached()
{
    augtool_helper /etc/sysconfig/memcached <<EOF
set PORT '"${MEMCACHED_INTERNAL_PORT}"'
EOF
}

configure_guacd()
{
    cat > /etc/one/guacd <<EOF
export OPTS=" -b 0.0.0.0 -l ${GUACD_INTERNAL_PORT}"
EOF
}

configure_fireedge()
{
    onecfg_helper /etc/one/fireedge-server.conf <<EOF
SET port ${FIREEDGE_INTERNAL_PORT}
SET one_xmlrpc "http://${ONED_HOST}:${ONED_INTERNAL_PORT}/RPC2"
SET oneflow_server "http://${ONEFLOW_HOST}:${ONEFLOW_INTERNAL_PORT}"
SET oneprovision_prepend_command "ssh -t -p ${ONEPROVISION_PORT} ${ONEPROVISION_HOST}"
SET guacd {}
SET guacd/host "${GUACD_HOST}"
SET guacd/port ${GUACD_INTERNAL_PORT}
EOF

    # TODO: remove when FireEdge is fixed
    cat /etc/one/fireedge-server.conf > /usr/lib/one/fireedge/dist/fireedge-server.conf
}

configure_scheduler()
{
    onecfg_helper /etc/one/sched.conf <<EOF
set ONE_XMLRPC "\"http://${ONED_HOST}:${ONED_INTERNAL_PORT}/RPC2\""
EOF
}

configure_oneflow()
{
    onecfg_helper /etc/one/oneflow-server.conf <<EOF
SET :one_xmlrpc "http://${ONED_HOST}:${ONED_INTERNAL_PORT}/RPC2"
SET :host "0.0.0.0"
SET :port ${ONEFLOW_INTERNAL_PORT}
EOF
}

configure_onegate()
{
    onecfg_helper /etc/one/onegate-server.conf <<EOF
SET :one_xmlrpc "http://${ONED_HOST}:${ONED_INTERNAL_PORT}/RPC2"
SET :oneflow_server "http://${ONEFLOW_HOST}:${ONEFLOW_INTERNAL_PORT}"
SET :host "0.0.0.0"
SET :port ${ONEGATE_INTERNAL_PORT}
EOF
}

configure_mysqld()
{
    # ensure that the mysql directory is owned by mysql user and has correct
    # permissions
    chown -R mysql:mysql /var/lib/mysql
    chmod 0755 /var/lib/mysql

    # populate service env file
    cat > /etc/default/supervisor/mysqld <<EOF
export MYSQL_HOST="${MYSQL_HOST}"
export MYSQL_PORT="${MYSQL_PORT}"
export MYSQL_DATABASE="${MYSQL_DATABASE}"
export MYSQL_USER="${MYSQL_USER}"
export MYSQL_PASSWORD="${MYSQL_PASSWORD}"
export MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD}"
EOF
}

configure_docker()
(
    # setup docker socket which will be used in all cases
    _docker_hosts="--host=unix://${DIND_SOCKET}"

    if is_true "${DIND_TCP_ENABLED}" ; then
        # just add space if needed
        _docker_hosts="${_docker_hosts}${_docker_hosts:+ }"

        # expose docker daemon via TCP
        _docker_hosts="${_docker_hosts}--host=tcp://${DIND_HOST}:${DIND_INTERNAL_PORT}"
    fi

    # populate service env file
    cat > /etc/default/supervisor/dockerd <<EOF
export DOCKERD_SOCK="${DIND_SOCKET}"
export DOCKER_HOSTS="${_docker_hosts}"
EOF
)

configure_oneprovision()
{
    _oneprovision_service="oneprovision-sshd"

    # we don't want the ssh port to collide with the other sshd service if
    # running via podman or as all-in-one
    cat >> /etc/sysconfig/sshd <<EOF
if [ "\${SUPERVISOR_PROCESS_NAME}" = "${_oneprovision_service}" ] ; then
    export OPTIONS="\${OPTIONS} -p ${ONEPROVISION_PORT} "
fi
EOF

    # generate oneprovision.sh to guard ssh commands
    cat > /usr/local/bin/oneprovision.sh <<EOF
#!/bin/sh

ONE_XMLRPC="http://${ONED_HOST}:${ONED_INTERNAL_PORT}/RPC2"
export ONE_XMLRPC

case "\$1" in
    oneprovision|oneprovision-template|oneprovider)
        :
        ;;
    *)
        echo "ERROR: only oneprovision commands are allowed" >&2
        exit 1
        ;;
esac

exec "\$@"
EOF

    chown root: /usr/local/bin/oneprovision.sh
    chmod 0755 /usr/local/bin/oneprovision.sh
}

add_oneprovision_service()
{
    _oneprovision_service="oneprovision-sshd"

    # reuse sshd as a template for supervisor service
    msg "SUPERVISORD: Add service '/etc/supervisord.d/${_oneprovision_service}.ini'"
    cp -a "/usr/share/one/supervisor/supervisord.d/sshd.ini" \
        /etc/supervisord.d/${_oneprovision_service}.ini
    sed -i "1s/program:sshd/program:${_oneprovision_service}/" \
        /etc/supervisord.d/${_oneprovision_service}.ini
}

oned_sanity_check()
{
    if [ -z "${OPENNEBULA_FRONTEND_HOST}" ] ; then
        err "ONED: Empty 'OPENNEBULA_FRONTEND_HOST' - ABORT"
        exit 1
    fi

    if [ -z "${OPENNEBULA_FRONTEND_SSH_HOST}" ] ; then
        err "ONED: Empty 'OPENNEBULA_FRONTEND_SSH_HOST' - ABORT"
        exit 1
    fi

    if [ -z "$MYSQL_PASSWORD" ] ; then
        err "ONED: Empty 'MYSQL_PASSWORD' - ABORT"
        exit 1
    fi
}

sunstone_sanity_check()
{
    if [ -z "${OPENNEBULA_FRONTEND_HOST}" ] ; then
        err "SUNSTONE: Empty 'OPENNEBULA_FRONTEND_HOST' - ABORT"
        exit 1
    fi

    if is_true "${SUNSTONE_HTTPS_ENABLED}" ; then
        if ! [ -f /srv/one/secret-tls/one.crt ] || ! [ -f /srv/one/secret-tls/one.key ] ; then
            err "SUNSTONE: HTTPS requested but no certs provided - ABORT"
            exit 1
        fi
    fi
}

mysqld_sanity_check()
{
    if [ "$OPENNEBULA_FRONTEND_SERVICE" = "all" ] ; then
        # for convenience when mysqld and oned are running together
        if [ -z "$MYSQL_PASSWORD" ] ; then
            msg "MYSQLD: Empty 'MYSQL_PASSWORD' - generate random"
            MYSQL_PASSWORD=$(gen_password ${PASSWORD_LENGTH})
        fi
    else
        # but if not run together
        if [ -z "$MYSQL_PASSWORD" ] ; then
            err "MYSQLD: Empty 'MYSQL_PASSWORD' - ABORT"
            exit 1
        fi
    fi

    # no one except mysqld itself should need root password
    if [ -z "$MYSQL_ROOT_PASSWORD" ] ; then
        msg "MYSQLD: Empty 'MYSQL_ROOT_PASSWORD' - generate random"
        MYSQL_ROOT_PASSWORD=$(gen_password ${PASSWORD_LENGTH})
    fi
}

fix_docker_socket()
{
    if ! [ -e "${DIND_SOCKET}" ] ; then
        err "DOCKER: No docker socket (${DIND_SOCKET}) - SKIP"
        return 0
    fi

    # save the gid of the docker.sock
    _docker_gid=$(stat -c %g "${DIND_SOCKET}")

    if getent group | grep -q '^docker:' ; then
        # we reassign the docker's GID to that of the actual docker.sock
        groupmod -g "$_docker_gid" docker
    else
        # we create docker group
        groupadd -r -g "$_docker_gid" docker
    fi
}

fix_docker_command()
(
    if is_true "${DIND_TCP_ENABLED}" ; then
        _docker_host="tcp://${DIND_HOST}:${DIND_INTERNAL_PORT}"
    else
        _docker_host="unix://${DIND_SOCKET}"
    fi

    cat > /usr/local/bin/docker <<EOF
#!/bin/sh

DOCKER_HOST="\${DOCKER_HOST:-${_docker_host}}"
export DOCKER_HOST

exec /usr/bin/docker "\$@"
EOF

    chown root: /usr/local/bin/docker
    chmod 0755 /usr/local/bin/docker
)

initialize_supervisord_conf()
{
    # respect the pre-existing config
    _DO_NOT_MODIFY_SUPERVISORD=
    if [ -f /etc/supervisord.conf ] ; then
        _DO_NOT_MODIFY_SUPERVISORD=yes
        msg "SUPERVISORD: Found existing '/etc/supervisord.conf' - SKIP"
        return 0
    fi

    # otherwise create an initial stub config
    msg "SUPERVISORD: Configure '/etc/supervisord.conf'"
    cp -a /usr/share/one/supervisor/supervisord.conf /etc/supervisord.conf

    # generate credentials so we avoid this warning message:
    # CRIT Server 'unix_http_server' running without any HTTP authentication checking
    msg "SUPERVISORD: Generate credentials"
    _supervisor_passwd=$(gen_password)

    # TODO: in the future this can be replaced with augtool_helper
    sed -i \
        -e "s/^username=.*/username=supervisor_user/g" \
        -e "s/^password=.*/password=${_supervisor_passwd}/g" \
        /etc/supervisord.conf

    # TODO: Either disable Control socket in ~onedmin/.ssh/config or somehow
    # encapsulate ssh command to not generate orphans...
    #
    # this will move the 'reaped unknown pid' log message to lower debug level
    # from the default info - unfortunately ssh control socket mechanism is
    # generating this message every 1-2 minutes and it spams the container's
    # stdout - moving the loglevel to warn would mute *EVERY* normal output as
    # is generated via echo or msg function in this script...
    msg "SUPERVISORD: Remove 'process reaping' messages from the INFO log level"
    for _script in /usr/lib/python*/site-packages/supervisor/supervisord.py ; do
        if [ -f "${_script}" ] ; then
            sed -i \
                's#self.options.logger.info(\(.\)reaped unknown pid#self.options.logger.debug(\1reaped unknown pid#g' \
                "${_script}"
        fi
    done
}

# arg: <service name>
add_supervised_service()
{
    # TODO: improve or delete this - it breaks bootstrap when container is
    # restarted on failure...
    #
    # do not alter the configuration if supervisord.conf was already provided
    #if [ -n "$_DO_NOT_MODIFY_SUPERVISORD" ] ; then
    #    msg "SUPERVISORD: Custom supervisord.conf - SKIP: ${1}.ini"
    #    return 0
    #fi

    msg "SUPERVISORD: Add service '/etc/supervisord.d/${1}.ini'"
    cp -a "/usr/share/one/supervisor/supervisord.d/${1}.ini" /etc/supervisord.d/
}

# NOTE: you may leave it or remove it once podman-compose stops duplicating
# lines in /etc/hosts
fix_hosts_file()
{
    # workaround for podman-compose which multiplicates lines in /etc/hosts by
    # as many as there are containers in the docker-compose file...
    #
    # this results in an invalid /etc/hosts file and dockerd fails to process
    # such file

    cat /etc/hosts | awk '
    BEGIN {
        linecount = 0;
    }
    {
        if (seen[$0] != "yes") {
            seen[$0] = "yes";
            lines[++linecount] = $0;
        }
    }
    END {
        for (i = 1; i <= linecount; ++i)
            print lines[i];
    }
    ' > /etc/hosts.tmp

    cat /etc/hosts.tmp > /etc/hosts
    rm -f /etc/hosts.tmp
}

cleanup_tmpdirs()
{
    # try to delete all temporary files
    for _tmp_dir in /tmp /run /run/lock ; do
        if [ -d "${_tmp_dir}" ] ; then
            find "${_tmp_dir}" \
                -mindepth 1 \
                -maxdepth 1 \
                -exec rm -rf '{}' \; \
                || true
        fi
    done
}

fix_volume_ownership()
{
    # podman does not respect ownership of directories when volume is mounted -
    # these must be then explicitly stated during bootstrap
    #
    # setup which does not fit anywhere else can be here...

    # opennebula shared log directory
    chown -R "${ONEADMIN_USERNAME}:" /var/log/one
    chmod 0750 /var/log/one

    # oneadmin's directories

    # datastore
    chown -R "${ONEADMIN_USERNAME}:" /var/lib/one/datastores
    chmod 0750 /var/lib/one/datastores

    # backups and db
    mkdir -p /var/lib/one/backups/db
    chown -R "${ONEADMIN_USERNAME}:" /var/lib/one/backups
    chmod 0750 /var/lib/one/backups
    chmod 0750 /var/lib/one/backups/db
}


# needed if OPENNEBULA_FRONTEND_SSH_HOST is not resolvable from within the
# container - useful in all-in-one deployment or if using podman (cause its
# containers share the network namespace and are basically reachable on the
# localhost)
resolve_frontend_hostname()
{
    echo 127.0.0.1 "$OPENNEBULA_FRONTEND_SSH_HOST" \
        >> /etc/hosts
}

common_configuration()
{
    msg "FRONTEND: Clean up non-persistent directories"
    cleanup_tmpdirs

    msg "FRONTEND: Fix ownership of the volume paths"
    fix_volume_ownership

    msg "FRONTEND: Fix hosts file (/etc/hosts)"
    fix_hosts_file

    msg "FRONTEND: Create system tmpfiles"
    create_common_tmpfiles

    msg "FRONTEND: Create oneadmin's tmpfiles"
    create_oneadmin_tmpfiles

    if [ "$OPENNEBULA_FRONTEND_SERVICE" = "all" ] ; then
        # this is needed if user does not provide proper hostnames
        resolve_frontend_hostname
    fi
}

#
# frontend services
#

stunnel_srv()
{
    # prepare TLS proxy service
    if is_true "${TLS_PROXY_ENABLED}" ; then
        msg "STUNNEL: Setup service"
        add_supervised_service stunnel
    fi
}

sshd_srv()
{
    msg "SSHD: Create ssh tmpfiles"
    create_ssh_tmpfiles

    msg "SSHD: Prepare ssh host keys"
    restore_ssh_host_keys

    msg "SSHD: Remove nologin files"
    rm -f /etc/nologin /run/nologin

    msg "SSHD: Setup service"
    add_supervised_service sshd
}

oneprovision_srv()
{
    if [ "$OPENNEBULA_FRONTEND_SERVICE" = "oneprovision" ] ; then
        msg "OPENNEBULA PROVISION: Create ssh tmpfiles"
        create_ssh_tmpfiles

        msg "OPENNEBULA PROVISION: Prepare ssh host keys"
        restore_ssh_host_keys

        msg "OPENNEBULA PROVISION: Remove nologin files"
        rm -f /etc/nologin /run/nologin

        msg "OPENNEBULA PROVISION: Prepare oneadmin's ssh"
        prepare_ssh_oneadmin_provision
    fi

    msg "OPENNEBULA PROVISION: Generate ssh key"
    prepare_ssh_oneprovision

    msg "OPENNEBULA PROVISION: Configure service"
    configure_oneprovision

    msg "OPENNEBULA PROVISION: Setup service"
    add_oneprovision_service
}

mysqld_srv()
{
    msg "MYSQLD: Create mysql tmpfiles"
    create_mariadb_tmpfiles

    msg "MYSQLD: Sanity check"
    mysqld_sanity_check

    msg "MYSQLD: Configure service"
    configure_mysqld

    msg "MYSQLD: Setup service"
    add_supervised_service mysqld
    add_supervised_service mysqld-upgrade
    add_supervised_service mysqld-configure
}

docker_srv()
{
    if is_true "${DIND_ENABLED}" ; then
        msg "DOCKER: Configure service"
        configure_docker

        msg "DOCKER: Fix docker command"
        fix_docker_command

        msg "DOCKER: Setup service"
        add_supervised_service containerd
        add_supervised_service docker
    fi
}

oned_srv()
{
    msg "OPENNEBULA ONED: Fix docker socket"
    fix_docker_socket

    if [ "$OPENNEBULA_FRONTEND_SERVICE" = "oned" ] ; then
        msg "OPENNEBULA ONED: Fix docker command"
        fix_docker_command
    fi

    msg "OPENNEBULA ONED: Prepare oneadmin's one_auth"
    prepare_oneadmin_auth

    msg "OPENNEBULA ONED: Prepare oneadmin's ssh"
    prepare_ssh

    if is_true "${TLS_PROXY_ENABLED}" ; then
        msg "OPENNEBULA ONED: Prepare certificate"
        prepare_cert

        msg "OPENNEBULA ONED: Configure TLS proxy"
        configure_tlsproxy oned
    fi

    msg "OPENNEBULA ONED: Sanity check"
    oned_sanity_check

    msg "OPENNEBULA ONED: Configure service"
    configure_oned

    msg "OPENNEBULA ONED: Setup logrotate"
    cp -a /etc/logrotate.one/opennebula /etc/logrotate.d/

    msg "OPENNEBULA ONED: Setup service"
    add_supervised_service opennebula
    add_supervised_service opennebula-ssh-agent
    add_supervised_service opennebula-ssh-add
    add_supervised_service opennebula-ssh-socks-cleaner
    add_supervised_service opennebula-showback
}

sunstone_srv()
{
    msg "OPENNEBULA SUNSTONE: Create httpd tmpfiles"
    create_httpd_tmpfiles

    if is_true "${SUNSTONE_HTTPS_ENABLED}" ; then
        msg "OPENNEBULA SUNSTONE: Prepare certificate"
        prepare_cert
    fi

    msg "OPENNEBULA SUNSTONE: Sanity check"
    sunstone_sanity_check

    msg "OPENNEBULA SUNSTONE: Configure service"
    configure_sunstone

    msg "OPENNEBULA SUNSTONE: Setup logrotate"
    cp -a /etc/logrotate.one/opennebula-sunstone /etc/logrotate.d/
    cp -a /etc/logrotate.one/opennebula-novnc /etc/logrotate.d/

    msg "OPENNEBULA SUNSTONE: Setup service"
    add_supervised_service opennebula-httpd
    add_supervised_service opennebula-novnc
}

guacd_srv()
{
    msg "GUACD: Configure service"
    configure_guacd

    msg "GUACD: Setup service"
    add_supervised_service opennebula-guacd
}

fireedge_srv()
{
    msg "OPENNEBULA FIREEDGE: Configure service"
    configure_fireedge

    msg "OPENNEBULA FIREEDGE: Setup logrotate"
    cp -a /etc/logrotate.one/opennebula-fireedge /etc/logrotate.d/

    msg "OPENNEBULA FIREEDGE: Setup service"
    add_supervised_service opennebula-fireedge
}

memcached_srv()
{
    msg "MEMCACHED: Configure service"
    configure_memcached

    msg "MEMCACHED: Setup service"
    add_supervised_service memcached
}

scheduler_srv()
{
    msg "OPENNEBULA SCHEDULER: Configure service"
    configure_scheduler

    msg "OPENNEBULA SCHEDULER: Setup logrotate"
    cp -a /etc/logrotate.one/opennebula-scheduler /etc/logrotate.d/

    msg "OPENNEBULA SCHEDULER: Setup service"
    add_supervised_service opennebula-scheduler
}

oneflow_srv()
{
    msg "OPENNEBULA FLOW: Configure service"
    configure_oneflow

    if is_true "${TLS_PROXY_ENABLED}" ; then
        msg "OPENNEBULA FLOW: Configure TLS proxy"
        configure_tlsproxy oneflow
    fi

    msg "OPENNEBULA FLOW: Setup logrotate"
    cp -a /etc/logrotate.one/opennebula-flow /etc/logrotate.d/

    msg "OPENNEBULA FLOW: Setup service"
    add_supervised_service opennebula-flow
}

onegate_srv()
{
    msg "OPENNEBULA GATE: Configure service"
    configure_onegate

    if is_true "${TLS_PROXY_ENABLED}" ; then
        msg "OPENNEBULA GATE: Configure TLS proxy"
        configure_tlsproxy onegate
    fi

    msg "OPENNEBULA GATE: Setup logrotate"
    cp -a /etc/logrotate.one/opennebula-gate /etc/logrotate.d/

    msg "OPENNEBULA GATE: Setup service"
    add_supervised_service opennebula-gate
}

onehem_srv()
{
    # TODO: does it make sense to run separately from oned? (can be even?)

    msg "OPENNEBULA HEM: Setup logrotate"
    cp -a /etc/logrotate.one/opennebula-hem /etc/logrotate.d/

    msg "OPENNEBULA HEM: Setup service"
    add_supervised_service opennebula-hem
}

###############################################################################
# start service
#

msg "FRONTEND: Set trap on exit"
trap on_exit EXIT
trap sig_exit INT QUIT TERM

# run pre-bootstrap hook if any
if [ -n "${OPENNEBULA_FRONTEND_PREHOOK}" ] \
    && [ -f "${OPENNEBULA_FRONTEND_PREHOOK}" ] \
    && [ -x "${OPENNEBULA_FRONTEND_PREHOOK}" ] ;
then
    msg "FRONTEND: Pre-bootstrap hook found - running: '${OPENNEBULA_FRONTEND_PREHOOK}'"
    "${OPENNEBULA_FRONTEND_PREHOOK}"
fi

msg
msg "***************************************"
msg "**********  BOOTSTRAP START  **********"
msg "***************************************"
msg

# shared steps for all containers
common_configuration
initialize_supervisord_conf

# this is mandatory for logrotate and it also functions as a more meaningful
# replacement for the infinite loop service
msg "CROND: Setup service"
add_supervised_service crond

msg
msg ">>> FRONTEND SERVICE: [${OPENNEBULA_FRONTEND_SERVICE}] <<<"
msg

case "${OPENNEBULA_FRONTEND_SERVICE}" in
    none)
        # supervisord needs at least one program section...should not be needed
        # thanks to the crond but just in case...
        msg "FRONTEND: Setup service"
        add_supervised_service infinite-loop
        ;;
    all)
        sshd_srv
        oneprovision_srv
        mysqld_srv
        docker_srv
        oned_srv
        stunnel_srv
        scheduler_srv
        oneflow_srv
        onegate_srv
        onehem_srv
        sunstone_srv
        memcached_srv
        guacd_srv
        fireedge_srv
        ;;
    oned)
        oned_srv
        onehem_srv
        stunnel_srv
        ;;
    sshd)
        sshd_srv
        ;;
    mysqld)
        mysqld_srv
        ;;
    docker)
        docker_srv
        ;;
    memcached)
        memcached_srv
        ;;
    sunstone)
        sunstone_srv
        ;;
    guacd)
        guacd_srv
        ;;
    fireedge)
        fireedge_srv
        ;;
    scheduler)
        scheduler_srv
        ;;
    oneflow)
        oneflow_srv
        stunnel_srv
        ;;
    onegate)
        onegate_srv
        stunnel_srv
        ;;
    oneprovision)
        oneprovision_srv
        ;;
    *)
        err "UNKNOWN FRONTEND SERVICE: '${OPENNEBULA_FRONTEND_SERVICE}' - ABORT"
        exit 1
        ;;
esac

msg "FRONTEND: Delete workfiles"
execute_delete_list

msg
msg "***************************************"
msg "**********  BOOTSTRAP  END   **********"
msg "***************************************"
msg

# run post-bootstrap hook if any
if [ -n "${OPENNEBULA_FRONTEND_POSTHOOK}" ] \
    && [ -f "${OPENNEBULA_FRONTEND_POSTHOOK}" ] \
    && [ -x "${OPENNEBULA_FRONTEND_POSTHOOK}" ] ;
then
    msg "FRONTEND: Post-bootstrap hook found - running: '${OPENNEBULA_FRONTEND_POSTHOOK}'"
    "${OPENNEBULA_FRONTEND_POSTHOOK}"
fi

# custom onecfg patch
if [ -n "${OPENNEBULA_FRONTEND_ONECFG_PATCH}" ] \
   && [ -f "${OPENNEBULA_FRONTEND_ONECFG_PATCH}" ] ;
then
    msg "ONECFG: Apply user-provided patch: '${OPENNEBULA_FRONTEND_ONECFG_PATCH}'"
    onecfg patch --all "${OPENNEBULA_FRONTEND_ONECFG_PATCH}"
fi

if is_true "${MAINTENANCE_MODE}" ; then
        msg "MAINTENANCE MODE: Disable autostart of all frontend services"

        # disable autostart for all configured and enabled services
        sed -i \
            -e '/^[[:space:]]*autostart=/d' \
            -e '$s/.*/&\nautostart=false/' \
            /etc/supervisord.d/*.ini

        # supervisord needs at least one program section...
        msg "FRONTEND: Setup service"
        add_supervised_service infinite-loop
fi

msg "FRONTEND: Exec supervisord"
exec env -i PATH="${PATH}" /usr/bin/supervisord -n -c /etc/supervisord.conf

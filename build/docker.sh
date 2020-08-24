#!/bin/sh

# This script builds docker images with the dockerized OpenNebula

set -e

#
# directives
#

# if DISTRO is not set then try to deduce it from the running name - we expect
# that the name fits the following scheme:
#   <distro>-container*

CMD=$(basename "${0}")
WORKDIR=$(dirname "${0}")

DISTRO="${DISTRO:-${CMD%%-container*}}"

DOCKER_CMD="${DOCKER_CMD:-podman}"
DOCKER_EXTRA_ARGS="${DOCKER_EXTRA_ARGS:---squash --pull}"
DOCKER_PATH="./templates/${DISTRO}-container/"
DOCKER_FILE="./templates/${DISTRO}-container/Dockerfile-frontend"


# ARG1 OR OPENNEBULA_URL_REPO
if [ -z "$OPENNEBULA_URL_REPO" ] ; then
    if [ -z "$1" ] ; then
        echo "ERROR: Missing repo argument (or 'OPENNEBULA_URL_REPO')" >&2
        exit 1
    else
        OPENNEBULA_URL_REPO=$(echo "$1" | \
            sed -n 's#^\(https\?://services/build/[^/]\+\)/.*#\1#p')
        if [ -z "$OPENNEBULA_URL_REPO" ] ; then
            echo "ERROR: URL is in wrong format: '${1}'" >&2
            exit 1
        else
            OPENNEBULA_URL_REPO="${OPENNEBULA_URL_REPO}/centos8/repo"
        fi
    fi
fi

# ARG2 OR OPENNEBULA_VERSION
if [ -z "$OPENNEBULA_VERSION" ] ; then
    if [ -z "$2" ] ; then
        echo "ERROR: Missing version argument (or 'OPENNEBULA_VERSION')" >&2
        exit 1
    else
        OPENNEBULA_VERSION="$2"
    fi
fi

# optional
OPENNEBULA_EDITION="${OPENNEBULA_EDITION:+-}${OPENNEBULA_EDITION}"
# TODO: OPENNEBULA_TOKEN="${OPENNEBULA_TOKEN}"

# prepare repo docker build args
case "$DISTRO" in
    centos8)
        OPENNEBULA_URL_REPO="${OPENNEBULA_URL_REPO}/CentOS/\$releasever/\$basearch"
        OPENNEBULA_URL_GPGKEY="${OPENNEBULA_URL_GPGKEY:-https://downloads.opennebula.io/repo/repo.key}"
        ;;
    *)
        # unsupported distro
        echo "ERROR: Invalid target '${DISTRO}'" >&2
        exit 1
        ;;
esac

# docker image name
IMAGE_NAME="opennebula-frontend"
IMAGE_TAG="${OPENNEBULA_VERSION}${OPENNEBULA_EDITION}-$(date +%s)"

#
# main
#

cd "$WORKDIR"

if ! command -v "${DOCKER_CMD}" >/dev/null 2>&1 ; then
    cat >&2 <<EOF
[!] missing docker-compliant cli command: ${DOCKER_CMD}
    Try to install either 'docker' or 'podman' and set the 'DOCKER_CMD' env.
    variable accordingly.
EOF

    exit 1
fi

# build image
${DOCKER_CMD} build ${DOCKER_EXTRA_ARGS} \
    --build-arg OPENNEBULA_VERSION="${OPENNEBULA_VERSION}" \
    --build-arg OPENNEBULA_URL_REPO="${OPENNEBULA_URL_REPO}" \
    --build-arg OPENNEBULA_URL_GPGKEY="${OPENNEBULA_URL_GPGKEY}" \
    -f "${DOCKER_FILE}" \
    -t "${IMAGE_NAME}:${IMAGE_TAG}" \
    "${DOCKER_PATH}"

# save image
rm -rf ~/tar
mkdir -p ~/tar
${DOCKER_CMD} save "${IMAGE_NAME}:${IMAGE_TAG}" | \
    gzip > ~/tar/"${IMAGE_NAME}:${IMAGE_TAG}.tar.gz"

exit 0

#!/usr/bin/env bash

################################################################################
#
# Mandatory arguments:
# $1 - URL (e.g. http://services/build/5.13.80-X-Y-Z/opennebula-5.13.80.tar.gz)
# $2 - Package version (currently 1 for CE or 2 for EE)
#
# Environmental variables which might affect the build:
# BUILD_COMPONENTS    - List of built OpenNebula components (e.g. fireedge)
# CONTACT             - OpenNebula contact info (e.g. email)
# DISTRO              - Base image for containers (e.g. centos8)
# TEMPLATES           - Subdirectory of templates (e.g. centos8-container)
# VERSION             - Full OpenNebula version (e.g. 5.13.80)
# DOCKER_CMD          - Runtime binary (currently docker or podman)
# DOCKER_EXTRA_ARGS   - Extra arguments for container runtime (e.g. --squash)
# DEBUG               - If set (to anything) it will skip the save and tar
#
# Image metadata environmental variables:
# OPENNEBULA_URL_REPO   - Base URL of custom repository (overrides ARG 1)
# OPENNEBULA_URL_GPGKEY - URL of the repo GPG key
# OPENNEBULA_VERSION    - Major.Minor version (e.g. 5.13 - for repo usage only)
# OPENNEBULA_LICENSE    - Package license (e.g.: "Apache 2.0")
# IMAGE_TAG             - Image tag (defaults to <VERSION>-<ARG2>-<DATE>)
# IMAGE_VERSION         - Image version (defaults to IMAGE_TAG)
################################################################################

set -e -o pipefail

export LANG="en_US.UTF-8"

# distro code name
DISTRO=${DISTRO:-$(basename "$0")}
DISTRO=${DISTRO%.*}                         # strip .sh
DISTRO_FULL=${DISTRO}
DISTRO=${DISTRO%%-*}                        # strip flavour

# ARG1 OR OPENNEBULA_URL_REPO
if [ -z "$OPENNEBULA_URL_REPO" ] ; then
    if [ -z "$1" ] ; then
        echo "ERROR: Missing repo argument (or 'OPENNEBULA_URL_REPO')" >&2
        exit 1
    else
        SERVICES_URL=$(echo "$1" | \
            sed -n 's#^\(https\?://services/build/[^/]\+\)/.*#\1#p')

        if [ -z "$SERVICES_URL" ] ; then
            echo "ERROR: URL is in wrong format: '${1}'" >&2
            exit 1
        fi
    fi
fi

if [[ "${DISTRO}" =~ ^centos8 ]]; then
    OPENNEBULA_URL_REPO="${OPENNEBULA_URL_REPO:-${SERVICES_URL}/centos8/repo}"
    OPENNEBULA_URL_REPO="${OPENNEBULA_URL_REPO}/CentOS/\$releasever/\$basearch"
    OPENNEBULA_URL_GPGKEY="${OPENNEBULA_URL_GPGKEY:-https://downloads.opennebula.io/repo/repo.key}"
else
    echo "ERROR: Invalid target '${DISTRO}'" >&2
    exit 1
fi

###

cd "$(dirname "$0")"

BUILD_DIR=$(mktemp -d)
TEMPLATES=${TEMPLATES:-${DISTRO_FULL}}

URL="$1"
PKG_VERSION=${2:-1}

SOURCE=$(basename "${URL}")                 # opennebula-5.13.80.tar.gz
PACKAGE="${SOURCE%.tar.gz}"                 # opennebula-5.13.80

NAME=$(echo "${PACKAGE}" | cut -d'-' -f1)   # opennebula
VERSION=${VERSION:-$(echo "${PACKAGE}" | cut -d'-' -f2)}   # 5.13.80
CONTACT=${CONTACT:-Unofficial Unsupported Build}
BASE_NAME="${NAME}-${VERSION}-${PKG_VERSION}"
DATE=$(date +'%Y%m%d%H%M')

DOCKER_CMD="${DOCKER_CMD:-podman}"
DOCKER_EXTRA_ARGS="${DOCKER_EXTRA_ARGS:---squash --pull}"

################################################################################
# Functions
################################################################################

# returns:
# 0 if enterprise (true)
# 1 if not (false)
is_enterprise()
{
    _ee=$(echo "$BUILD_COMPONENTS" | \
        sed -n 's/.*\<enterprise\>.*/yes/p' | \
        sort -u)

    if [ "${_ee}" = "yes" ] ; then
        return 0
    fi

    return 1
}

################################################################################
# Image metadata
################################################################################

# TODO: OPENNEBULA_TOKEN="${OPENNEBULA_TOKEN}"
OPENNEBULA_VERSION=${OPENNEBULA_VERSION:-${VERSION%.*}}

if [ -z "${OPENNEBULA_LICENSE}" ] && is_enterprise ; then
    echo '***** Using the enterprise license' >&2
    OPENNEBULA_LICENSE="OpenNebula Software License"
else
    echo '***** Using the community license' >&2
    OPENNEBULA_LICENSE="Apache-2.0"
fi

#IMAGE_NAME is set below (dynamically based on Dockerfile)
IMAGE_TAG="${IMAGE_TAG:-${VERSION}-${PKG_VERSION}-${DATE}}"
if [ -z "${DEBUG}" ] ; then
    # normal image version (with potentially variable version due to the date)
    IMAGE_VERSION="${IMAGE_VERSION:-${IMAGE_TAG}}"
else
    # debug image version (omitting variable portion - date - to reuse layers)
    IMAGE_VERSION="${VERSION}-${PKG_VERSION}"
fi

################################################################################
# Validations
################################################################################

if [ -z "$NAME" ] ; then
    echo "ERROR: Variable 'NAME' has no value due to the invalid url" >&2
    exit 1
fi

if [ -z "$VERSION" ] ; then
    echo "ERROR: No variable 'VERSION' and couldn't be deduced from url" >&2
    exit 1
fi

# check for docker
if ! command -v "${DOCKER_CMD}" >/dev/null 2>&1 ; then
    cat >&2 <<EOF
ERROR: Missing docker-compliant CLI command '${DOCKER_CMD}'
Try to install either 'docker' or 'podman' and set the 'DOCKER_CMD' env.
variable accordingly.
EOF

    exit 1
fi

################################################################################
# Build image(s)
################################################################################

# process all available Dockerfiles
# note: from Dockerfile-frontend built image opennebula
for DOCKER_FILE in "templates/${TEMPLATES}"/Dockerfile-*; do
    DOCKER_PATH=$(dirname "${DOCKER_FILE}")

    # construct image name from the Dockerfile suffix, e.g.:
    #   Dockerfile-frontend -> frontend -> opennebula
    IMAGE_NAME= # explicitly set to empty for safety
    DOCKER_NAME=$(basename "${DOCKER_FILE}" | sed -e 's/^Dockerfile-//')
    case "${DOCKER_NAME}" in
        frontend)
            # NOTE: based on the is_enterprise you could modify the name to
            # opennebula-ce/opennebula-ee
            IMAGE_NAME="opennebula"
            ;;
        # here you can add other names...
        node)
            IMAGE_NAME="${DOCKER_NAME}"
            ;;
        *)
            echo "ERROR: Unrecognized Dockerfile suffix: ${DOCKER_NAME} " >&2
            exit 1
            ;;
    esac

    # build image
    echo "***** Building image ${IMAGE_NAME}" >&2
    "${DOCKER_CMD}" build ${DOCKER_EXTRA_ARGS} \
        --build-arg IMAGE_NAME="${IMAGE_NAME}" \
        --build-arg IMAGE_VERSION="${IMAGE_VERSION}" \
        --build-arg OPENNEBULA_CONTACT="${CONTACT}" \
        --build-arg OPENNEBULA_LICENSE="${OPENNEBULA_LICENSE}" \
        --build-arg OPENNEBULA_VERSION="${OPENNEBULA_VERSION}" \
        --build-arg OPENNEBULA_URL_REPO="${OPENNEBULA_URL_REPO}" \
        --build-arg OPENNEBULA_URL_GPGKEY="${OPENNEBULA_URL_GPGKEY}" \
        -f "${DOCKER_FILE}" \
        -t "${IMAGE_NAME}:${IMAGE_TAG}" \
        "${DOCKER_PATH}"

    # skip if DEBUG=something
    if [ -z "${DEBUG}" ] ; then
        # export image
        echo "***** Exporting image ${IMAGE_NAME}" >&2
        "${DOCKER_CMD}" save "${IMAGE_NAME}:${IMAGE_TAG}" \
            -o "${BUILD_DIR}/${IMAGE_NAME}-${IMAGE_TAG}.tar"

        # include docker-compose.yml
        echo "***** Include docker-compose.yml" >&2
        cp -a "${DOCKER_PATH}/compose/frontend/docker-compose.yml" \
            "${BUILD_DIR}/"

        # include the default environment file
        cp -a "${DOCKER_PATH}/compose/frontend/default.env" \
            "${BUILD_DIR}/"
    fi
done

# TODO: fail if nothing was built

################################################################################
# Create archive with all images
################################################################################

# skip if DEBUG=something
if [ -z "${DEBUG}" ] ; then
    echo '***** Creating tar archive' >&2
    cd "${BUILD_DIR}"
    tar -czf "${BASE_NAME}.tar.gz" \
        --owner=root --group=root  \
        --transform "s,^,${BASE_NAME}/," \
        *

    # copy tar to ~/tar
    rm -rf ~/tar
    mkdir -p ~/tar
    mv -f "${BASE_NAME}.tar.gz" ~/tar
    ln -s "${BASE_NAME}.tar.gz" ~/tar/"${NAME}.tar.gz"
fi

################################################################################
# Cleanups
################################################################################

rm -rf "${BUILD_DIR}"

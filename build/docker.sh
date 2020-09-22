#!/usr/bin/env bash

####
# External parameters which might affect the build:
# OPENNEBULA_URL_REPO - base URL of custom repository
# OPENNEBULA_VERSION  - package version
# OPENNEBULA_EDITION  - edition of the OpenNebula to be build (CE/EE)
# OPENNEBULA_LICENSE  - package license (e.g.: "Apache 2.0")
# IMAGE_VERSION       - image version (it's unrelated with the OPENNEBULA_VERSION)

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

URL="$1"
PKG_VERSION=${2:-1}

TEMPLATES=${TEMPLATES:-${DISTRO_FULL}}
BUILD_DIR=$(mktemp -d)

SOURCE=$(basename "${URL}")
PACKAGE=${SOURCE%.tar.gz}
NAME=$(echo "${PACKAGE}" | cut -d'-' -f1) # opennebula
NAME=${NAME:-opennebula}
VERSION=${VERSION:-$OPENNEBULA_VERSION}
VERSION=${VERSION:-$(echo "${PACKAGE}" |cut -d'-' -f2)}   # 1.9.90
CONTACT=${CONTACT:-Unofficial Unsupported Build}
BASE_NAME="${NAME}-${VERSION}-${PKG_VERSION}"
DATE=$(date +'%Y%m%d%H%M')

DOCKER_CMD="${DOCKER_CMD:-podman}"
DOCKER_EXTRA_ARGS="${DOCKER_EXTRA_ARGS:---squash --pull}"

# image metadata
OPENNEBULA_EDITION=${OPENNEBULA_EDITION:-${PKG_VERSION}}
_is_enterprise=$(echo "$BUILD_COMPONENTS" | sed -n 's/.*\<enterprise\>.*/yes/p' | sort -u)
if [ -z "${OPENNEBULA_LICENSE}" ] && [ "${_is_enterprise}" = "yes" ] ; then
    echo '***** Using the enterprise license' >&2
    OPENNEBULA_LICENSE="OpenNebula Software License"
else
    echo '***** Using the community license' >&2
    OPENNEBULA_LICENSE="Apache-2.0"
fi
IMAGE_TAG="${VERSION}${OPENNEBULA_EDITION:+-${OPENNEBULA_EDITION}}-${DATE}"
IMAGE_VERSION="${IMAGE_VERSION:-1.0}"
# TODO: OPENNEBULA_TOKEN="${OPENNEBULA_TOKEN}"

################################################################################
# Validations
################################################################################

if [ -z "$VERSION" ] ; then
    echo "ERROR: Missing version arguments" >&2
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
# note: from Dockerfile-frontend built image opennebula-frontend
for DOCKER_FILE in "templates/${TEMPLATES}"/Dockerfile-*; do
    DOCKER_PATH=$(dirname "${DOCKER_FILE}")
    IMAGE_NAME=$(basename "${DOCKER_FILE}" | sed -e 's/^Dockerfile/opennebula/') #TODO

    # build image
    echo "***** Building image ${IMAGE_NAME}" >&2
    "${DOCKER_CMD}" build ${DOCKER_EXTRA_ARGS} \
        --build-arg OPENNEBULA_VERSION="${OPENNEBULA_VERSION}" \
        --build-arg OPENNEBULA_LICENSE="${OPENNEBULA_LICENSE}" \
        --build-arg IMAGE_VERSION="${IMAGE_VERSION}" \
        --build-arg OPENNEBULA_URL_REPO="${OPENNEBULA_URL_REPO}" \
        --build-arg OPENNEBULA_URL_GPGKEY="${OPENNEBULA_URL_GPGKEY}" \
        -f "${DOCKER_FILE}" \
        -t "${IMAGE_NAME}:${IMAGE_TAG}" \
        "${DOCKER_PATH}"

    # export image
    echo "***** Exporting image ${IMAGE_NAME}" >&2
    "${DOCKER_CMD}" save "${IMAGE_NAME}:${IMAGE_TAG}" \
        -o "${BUILD_DIR}/${IMAGE_NAME}-${IMAGE_TAG}.tar"

    # include docker-compose.yml
    echo "***** Include docker-compose.yml from examples" >&2
    cp -a "${DOCKER_PATH}/examples/onedocker-compose/docker-compose.yml" \
        "${BUILD_DIR}/"
done

# TODO: fail if nothing was built

################################################################################
# Create archive with all images
################################################################################

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

################################################################################
# Cleanups
################################################################################

rm -rf "${BUILD_DIR}"

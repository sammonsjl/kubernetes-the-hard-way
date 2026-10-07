#!/usr/bin/env bash
#
# Builds a container image of a Liferay you compiled yourself, for Lab 12.
#
#   liferay/build-image.sh <path to the bundle>
#
# The bundle is the folder `ant all` writes beside a liferay-portal checkout
# (../bundles): Tomcat, the OSGi modules and the Elasticsearch that Liferay
# starts beside itself. A source build needs no licence, which is the reason
# not to use the liferay/dxp image the chart defaults to.
#
# The image is built by Liferay's own tooling, liferay/liferay-docker, the
# same that builds liferay/dxp. The Helm chart depends on what that tooling
# produces: /opt/liferay, its entrypoint, and the pre-configure script folder.
#
# Run on your workstation. Needs: podman, git, rsync, unzip, curl, java.
#

set -o errexit
set -o nounset
set -o pipefail

BUNDLE=${1:?usage: build-image.sh <path to the bundle>}
IMAGE=${IMAGE:-localhost/kthw/liferay:source}
CACHE=${CACHE:-${HOME}/.cache/kubernetes-the-hard-way}
LIFERAY_DOCKER=${LIFERAY_DOCKER:-${CACHE}/liferay-docker}
# The liferay-docker commit this was last built with. Its Dockerfile starts
# FROM liferay/jdk21:latest, which moves: if the build fails in apt-get, the
# base image has moved past this commit. Try LIFERAY_DOCKER_REF=origin/master.
LIFERAY_DOCKER_REF=${LIFERAY_DOCKER_REF:-5d0054e9a5dbd104f7b54b23b8920f75c5345030}

if ! ls -d "${BUNDLE}"/tomcat-* > /dev/null 2>&1
then
	echo "${BUNDLE} has no tomcat-* folder: it is not a Liferay bundle." >&2

	exit 1
fi

WORK=$(mktemp --directory)

trap 'rm --force --recursive "${WORK}"' EXIT

# Step 1. Liferay's image tooling.

if [ ! -d "${LIFERAY_DOCKER}" ]
then
	git clone --quiet https://github.com/liferay/liferay-docker "${LIFERAY_DOCKER}"
fi

git -C "${LIFERAY_DOCKER}" fetch --quiet origin
git -C "${LIFERAY_DOCKER}" checkout --quiet "${LIFERAY_DOCKER_REF}"

# Step 2. A copy of the bundle without what belongs to the machine it has been
#   running on: its data, logs and state, and anything deployed into it since
#   it was built.

rsync --archive \
	--exclude '/data' --exclude '/logs/*' --exclude '/work' --exclude '/deploy/*' --exclude '/routes' \
	--exclude '/osgi/state' --exclude '/osgi/test' --exclude '/osgi/client-extensions/*' \
	--exclude '/osgi/modules/*' --exclude '/osgi/configs/*' \
	--exclude '/tomcat-*/logs/*' --exclude '/tomcat-*/temp/*' --exclude '/tomcat-*/work/*' \
	--exclude '/portal-ext.properties' --exclude '/portal-setup-wizard.properties' --exclude '/*.zip' \
	"${BUNDLE}/" "${WORK}/bundle/"

# The chart's init container copies data/* onto the volume, and fails on an
# empty folder.

mkdir --parents "${WORK}/bundle/data"
echo "Liferay's data folder. On Kubernetes this is the persistent volume." > "${WORK}/bundle/data/README.txt"

# Step 3. Liferay's build, with podman standing in for docker. It names the
#   image liferay<name>:<version>.

mkdir "${WORK}/bin"
printf '#!/bin/sh\nexec podman "$@"\n' > "${WORK}/bin/docker"
chmod +x "${WORK}/bin/docker"
printf 'unqualified-search-registries = ["docker.io"]\n' > "${WORK}/registries.conf"

(
	cd "${LIFERAY_DOCKER}"

	CONTAINERS_REGISTRIES_CONF="${WORK}/registries.conf" PATH="${WORK}/bin:${PATH}" \
		./build_local_image.sh "${WORK}/bundle" -kthw source --no-warm-up --no-test-image
) >&2

podman tag localhost/liferay-kthw:source "${IMAGE}"

# The build leaves two names of its own on the image, one of them timestamped.

podman image inspect --format '{{range .RepoTags}}{{println .}}{{end}}' "${IMAGE}" |
	grep '^localhost/liferay-kthw:' |
	xargs --no-run-if-empty podman untag "${IMAGE}" > /dev/null

echo "${IMAGE}"

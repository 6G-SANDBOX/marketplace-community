#!/usr/bin/env bash

set -o errexit -o pipefail
export DEBIAN_FRONTEND=noninteractive

REPO_URL="https://github.com/aligungr/UERANSIM"
REQUIRED_PACKAGES=("make" "gcc" "g++" "cmake" "curl" "libsctp-dev" "lksctp-tools" "iproute2")
REPOSITORY_PATH="$(dirname "$0").repository"
FILES_PATH="$(dirname "$0").files"
LOCK_FILE="/tmp/ueransim_build.lock"

# Avoid parallel executions of the script
if [ -f "$LOCK_FILE" ]; then
    echo "Another UERANSIM build process is already running. Exiting."
    exit 1
fi
touch "${LOCK_FILE}"

cleanup(){
  echo ""
  echo "ERROR: Something unexpected happened during the binary build script."
  rm -f "${LOCK_FILE}"
  exit 1
}
trap cleanup ERR


echo "Clone or update the UERANSIM repository"
if [ ! -d "${REPOSITORY_PATH}/.git" ]; then
    echo "Cloning UERANSIM at ${REPOSITORY_PATH}/ ..."
    rm -f "${REPOSITORY_PATH}/.placeholder"
    git clone "${REPO_URL}" "${REPOSITORY_PATH}/"
else
    echo "Pulling latest changes from origin to local..."
    cd "${REPOSITORY_PATH}/"
    git reset --hard HEAD
    git pull --rebase
    cd - > /dev/null
fi


echo "Install or update the required .deb packages"
apt-get update
for pkg in "${REQUIRED_PACKAGES[@]}"; do
    apt-get install -y "${pkg}"
done


echo "Build UERANSIM binaries"
cd "${REPOSITORY_PATH}/"
make -j
chmod +x build/nr-*
cd - > /dev/null


echo "Copy files into previously existing directories"
# rm -f "${FILES_PATH}/build/.placeholder"
cp -r "${REPOSITORY_PATH}/build/." "${FILES_PATH}/build/"
# rm -f "${FILES_PATH}/config/.placeholder"
cp -r "${REPOSITORY_PATH}/config/." "${FILES_PATH}/config/"

# Remove the lock file
rm -f "${LOCK_FILE}"
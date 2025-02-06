#!/usr/bin/env bash

set -o errexit -o pipefail
export DEBIAN_FRONTEND=noninteractive

BUILD_PACKAGES="make gcc g++ cmake"
BUILD_PATH="appliances/UERANSIM/UERANSIM"

if [ ! -d "${BUILD_PATH}" ]; then
    git clone https://github.com/aligungr/UERANSIM ${BUILD_PATH}
fi

if ! ls "${BUILD_PATH}"/build/nr-* &> /dev/null; then
    echo "UERANSIM binaries could not be found. Proceeding to make the necessary steps to build them..."

    echo "Install required packages"
    apt-get update
    if ! apt-get install -y ${BUILD_PACKAGES} curl libsctp-dev lksctp-tools iproute2; then
        echo "ERROR: Package(s) installation failed"
        exit 1
    fi
    
    echo "Build UERANSIM"
    cd ${BUILD_PATH}
    if ! make -j ; then
       echo "ERROR: Error building UERANSIM binaries"
       exit 1
    fi

    chmod +x build/nr-*

else
    echo "UERANSIM binaries found. Proceeding..."
fi
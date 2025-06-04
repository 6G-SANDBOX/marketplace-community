#!/usr/bin/env bash

set -o errexit -o pipefail

# ------------------------------------------------------------------------------
# Contextualization and global variables
# ------------------------------------------------------------------------------

DEP_PKGS="jq ubuntu-drivers-common"


# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# Mandatory Functions
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------

service_install()
{
    export DEBIAN_FRONTEND=noninteractive
    systemctl stop unattended-upgrades

    # Install the required debian packages
    install_prerequisites

    # Install the latest NVIDIA Open Source driver for ubuntu-server
    install_drivers

    # Install unofficial NVIDIA prometheus exporter
    install_exporter

    # cleanup
    postinstall_cleanup

    msg info "INSTALLATION FINISHED"

    return 0
}

service_configure()
{
    export DEBIAN_FRONTEND=noninteractive

    msg info "CONFIGURATION FINISHED"
    return 0
}

service_bootstrap()
{
    msg info "BOOTSTRAP FINISHED"
    return 0
}


# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# Function Definitions
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------

install_prerequisites()
{
    msg info "Run apt-get update"
    apt-get update

    msg info "Install required .deb packages"
    wait_for_dpkg_lock_release
    if ! apt-get install -y ${DEP_PKGS} ; then
        msg error "Installation of the prerequired packages failed"
        exit 1
    fi
}

install_drivers()
{
    msg info "Run apt-get update"
    apt-get update

    msg info "Install the latest NVIDIA drivers"
    wait_for_dpkg_lock_release
    LATEST_DRIVER=$(apt-cache search ^nvidia-driver | grep -i -server-open | awk '{print $1}' | sort -r | head -n1)
    if ! apt-get install -y "${LATEST_DRIVER}" ; then
        msg error "Installation of the latest NVIDIA drivers failed"
        exit 1
    fi
}

install_exporter()
{
    # https://github.com/utkuozdemir/nvidia_gpu_exporter
    msg info "Download the NVIDIA prometheus exporter from https://github.com/utkuozdemir/nvidia_gpu_exporter"

    LATEST_EXPORTER=$(curl -s https://api.github.com/repos/utkuozdemir/nvidia_gpu_exporter/releases/latest \
        | jq -r '.assets[] | select(.name | endswith("_amd64.deb")) | .browser_download_url')
    TEMP_DEB="$(mktemp)" &&
    wget -O "${TEMP_DEB}" "${LATEST_EXPORTER}"
    wait_for_dpkg_lock_release
    if ! dpkg -i "${TEMP_DEB}" ; then
        msg error "Installation of the NVIDIA Prometheus exporter failed"
        exit 1
    fi
    rm -f "${TEMP_DEB}"
}


wait_for_dpkg_lock_release()
{
  local lock_file="/var/lib/dpkg/lock-frontend"
  local timeout=600
  local interval=5

  for ((i=0; i<timeout; i+=interval)); do
    if ! lsof "${lock_file}" &>/dev/null; then
      return 0
    fi
    msg info "Could not get lock ${lock_file} due to unattended-upgrades. Retrying in ${interval} seconds..."
    sleep "${interval}"
  done

  msg error "Error: 10m timeout without ${lock_file} being released by unattended-upgrades"
  exit 1
}

postinstall_cleanup()
{
    msg info "Delete cache and stored packages"
    wait_for_dpkg_lock_release
    apt-get autoclean
    apt-get autoremove
    rm -rf /var/lib/apt/lists/*
}
#!/usr/bin/env bash

set -o errexit -o pipefail

# ------------------------------------------------------------------------------
# Contextualization and global variables
# ------------------------------------------------------------------------------

DESIRED_KERNEL="4.15.0-154-generic"
DEP_PKGS="python3.8 python3.8-distutils python3-pip sudo bison build-essential cmake flex git libedit-dev libllvm6.0 llvm-6.0-dev libclang-6.0-dev python zlib1g-dev libelf-dev libfl-dev apt-transport-https software-properties-common wget adduser libfontconfig1 musl"
INFLUXDB_VERSION="1.2.4"
GRAFANA_VERSION="9.5.3"

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# Service Implementation
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------

service_install()
{
    export DEBIAN_FRONTEND=noninteractive
    systemctl stop unattended-upgrades

    # Install specific kernel version
    install_kernel
    
    # Install dependencies
    install_deps

    # Install BCC
    install_bcc

    # Install INT-Collector
    install_int_collector

    # Install InfluxDB
    install_influxdb
    
    # Install Grafana
    install_grafana

    # Service metadata
    create_one_service_metadata

    # Cleanup
    postinstall_cleanup

    msg info "INSTALLATION FINISHED"

    return 0
}

service_configure()
{
    export DEBIAN_FRONTEND=noninteractive

    msg info "CONFIGURE FINISHED - Ansible is used to configure the rest"
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

install_kernel()
{
    #!/bin/bash
    set -e  # Exit on any error

    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        msg info "This script must be run as root (sudo)"
        exit 1
    fi

    # Install specific kernel
    msg info "Installing kernel ${DESIRED_KERNEL}..."
    wait_for_dpkg_lock_release
    apt-get update
    apt-get install -y linux-image-${DESIRED_KERNEL} linux-headers-${DESIRED_KERNEL}

    # Modify GRUB configuration
    msg info "Modifying GRUB configuration..."
    sed -i 's/GRUB_DEFAULT=.*/GRUB_DEFAULT="Advanced options for Ubuntu>Ubuntu, with Linux '"${DESIRED_KERNEL}"'"/' /etc/default/grub
    sed -i 's/#GRUB_DISABLE_SUBMENU=.*/GRUB_DISABLE_SUBMENU=false/' /etc/default/grub

    # Update GRUB
    msg info "Updating GRUB..."
    update-grub

    # Verify kernel installation
    #msg info "Verifying kernel installation..."
    #dpkg -l | grep -q "linux-image-${DESIRED_KERNEL}"
    #if ! dpkg -l | grep -q "linux-image-${DESIRED_KERNEL}"; then
    #    msg error "Kernel installation failed"
    #    exit 1
    #fi

    # Check kernel file in /boot
    if [ ! -f /boot/vmlinuz-${DESIRED_KERNEL} ]; then
        msg error "Kernel file not found in /boot"
        exit 1
    fi

    # Verify configuration in grub.cfg
    if ! grep -q "menuentry 'Ubuntu, with Linux ${DESIRED_KERNEL}'" /boot/grub/grub.cfg; then
        msg error "Kernel entry not found in GRUB menu"
        exit 1
    fi

    # Set boot order
    msg info "Setting boot order..."
    KERNEL_ENTRY="Advanced options for Ubuntu>Ubuntu, with Linux ${DESIRED_KERNEL}"
    grub-set-default "$KERNEL_ENTRY"
    grub-reboot "$KERNEL_ENTRY"  # Ensures this kernel is used on next boot

    msg info "Configuration completed. System will use kernel ${DESIRED_KERNEL} on next boot"
}


install_deps()
{
    msg info "Run apt-get update"
    apt-get update

    msg info "Install required packages for bcc, influxDB and Grafana"
    wait_for_dpkg_lock_release
    if ! apt-get install -y ${DEP_PKGS} ; then
        msg error "Package(s) installation failed"
        exit 1
    fi
}

install_bcc()
{
    msg info "Building BCC from source..."
    git clone https://github.com/iovisor/bcc.git
    cd bcc
    git checkout 14278bf1a52dd76ff66eed02cc9db7c7ec240da6
    
    mkdir -p build
    cd build/
    cmake ..
    make -j$(nproc)
    make install

    # Python3 specific build
    cmake -DPYTHON_CMD=python3 ..
    cd src/python
    make
    make install
}

install_int_collector()
{
    msg info "Installing INT-Collector..."
    cd /
    git clone https://github.com/GEANT-DataPlaneProgramming/int-collector.git
    cd int-collector
    pip3 install -r requirements.txt
}

install_influxdb()
{
    msg info "Installing Influxdb..."
    cd /
    wget https://dl.influxdata.com/influxdb/releases/influxdb_${INFLUXDB_VERSION}_amd64.deb
    dpkg -i influxdb_${INFLUXDB_VERSION}_amd64.deb
    systemctl start influxdb
    systemctl enable influxdb.service
}

install_grafana()
{
    msg info "Installing Grafana..."
    cd /
    wget https://dl.grafana.com/oss/release/grafana_${GRAFANA_VERSION}_amd64.deb
    dpkg -i grafana_${GRAFANA_VERSION}_amd64.deb
    systemctl daemon-reload
    systemctl start grafana-server
    systemctl enable grafana-server.service
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
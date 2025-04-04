#!/usr/bin/env bash

set -o errexit -o pipefail

# ------------------------------------------------------------------------------
# Global variables
# ------------------------------------------------------------------------------

ONE_SERVICE_RECONFIGURABLE=false

GRAFANA_ADMIN_USER="admin"

DEP_PKGS="build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev libffi-dev pkg-config wget apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common libgtk-3-0 libwebkit2gtk-4.0-37 libjavascriptcoregtk-4.0-18"

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# Mandatory Functions
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------

service_install()
{
  export DEBIAN_FRONTEND=noninteractive

  # packages
  install_pkg_deps

  # grafana
  install_grafana

  systemctl daemon-reload

  systemctl enable --now grafana-server.service

  # cleanup
  postinstall_cleanup

  msg info "INSTALLATION FINISHED"

  return 0
}

service_configure()
{
  export DEBIAN_FRONTEND=noninteractive

  configure_grafana

  msg info "CONFIGURATION FINISHED"
  return 0
}

service_bootstrap()
{
  export DEBIAN_FRONTEND=noninteractive

  msg info "BOOTSTRAP FINISHED"
  return 0
}


# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# Function Definitions
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------

install_pkg_deps()
{
  msg info "Run apt-get update"
  apt-get update

  msg info "Install required packages for ELCM"
  wait_for_dpkg_lock_release
  if ! apt-get install -y ${DEP_PKGS} ; then
    msg error "Package(s) installation failed"
    exit 1
  fi
}

install_grafana() {
  msg info "Install Grafana ${ONEAPP_GRAFANA_VERSION}"
  apt-get install -y adduser libfontconfig1 musl
  GRAFANA_URL="https://dl.grafana.com/oss/release/grafana_${ONEAPP_GRAFANA_VERSION}_amd64.deb"
  if wget --spider "${GRAFANA_URL}" 2>/dev/null; then
    msg info "Downloading Grafana ${ONEAPP_GRAFANA_VERSION}"
    wget "${GRAFANA_URL}"
    dpkg -i "grafana_${ONEAPP_GRAFANA_VERSION}_amd64.deb"
  else
    msg error "Grafana ${ONEAPP_GRAFANA_VERSION} not found at ${GRAFANA_URL}"
  fi
}

configure_grafana()
{
  msg info "Configure Grafana"
  grafana-cli ${GRAFANA_ADMIN_USER} reset-admin-password ${ONEAPP_GRAFANA_PASSWORD}
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

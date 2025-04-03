#!/usr/bin/env bash

set -o errexit -o pipefail

# ------------------------------------------------------------------------------
# Global variables
# ------------------------------------------------------------------------------

ONE_SERVICE_RECONFIGURABLE=true

ONEAPP_INFLUXDB_USER="${ONEAPP_INFLUXDB_USER:-admin}"
ONEAPP_INFLUXDB_ORG="${ONEAPP_ELCM_INFLUXDB_ORG:-dummyorg}"
ONEAPP_INFLUXDB_BUCKET="${ONEAPP_ELCM_INFLUXDB_BUCKET:-dummybucket}"
ONEAPP_INFLUXDB_HOST="127.0.0.1"
ONEAPP_INFLUXDB_PORT="8086"

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

  # influxdb
  install_influxdb

  systemctl daemon-reload

  # cleanup
  postinstall_cleanup

  msg info "INSTALLATION FINISHED"

  return 0
}

service_configure()
{
  export DEBIAN_FRONTEND=noninteractive

  # configure user, password and database influxdb
  configure_influxdb

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

install_influxdb()
{
  msg info "Install InfluxDB"
  wget -q https://repos.influxdata.com/influxdata-archive_compat.key
  echo '393e8779c89ac8d958f81f942f9ad7fb82a25e133faddaf92e15b16e6ac9ce4c influxdata-archive_compat.key' | sha256sum -c && cat influxdata-archive_compat.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/influxdata-archive_compat.gpg > /dev/null
  echo 'deb [signed-by=/etc/apt/trusted.gpg.d/influxdata-archive_compat.gpg] https://repos.influxdata.com/debian stable main' | sudo tee /etc/apt/sources.list.d/influxdata.list
  apt-get update
  apt-get install -y influxdb2
  systemctl enable --now influxdb.service
}

configure_influxdb()
{
  msg info "Configure InfluxDB"

  if influx user list --host http://${ONEAPP_INFLUXDB_HOST}:${ONEAPP_INFLUXDB_PORT} | grep -q "${ONEAPP_INFLUXDB_USER}"; then
    msg info "User ${ONEAPP_INFLUXDB_USER} already exists, skipping setup."
  else
    influx setup --host http://${ONEAPP_INFLUXDB_HOST}:${ONEAPP_INFLUXDB_PORT} \
      --org ${ONEAPP_INFLUXDB_ORG} \
      --bucket ${ONEAPP_INFLUXDB_BUCKET} \
      --username ${ONEAPP_INFLUXDB_USER} \
      --password ${ONEAPP_INFLUXDB_PASSWORD} \
      --force
  fi
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

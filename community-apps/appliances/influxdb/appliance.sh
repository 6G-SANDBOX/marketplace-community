#!/usr/bin/env bash

set -o errexit -o pipefail

# ------------------------------------------------------------------------------
# Global variables
# ------------------------------------------------------------------------------

ONE_SERVICE_RECONFIGURABLE=false

ONEAPP_INFLUXDB_VERSION="${ONEAPP_INFLUXDB_VERSION:-2.7.11}"
ONEAPP_INFLUXDB_USER="${ONEAPP_INFLUXDB_USER:-admin}"
ONEAPP_INFLUXDB_ORG="${ONEAPP_ELCM_INFLUXDB_ORG:-dummyorg}"
ONEAPP_INFLUXDB_BUCKET="${ONEAPP_ELCM_INFLUXDB_BUCKET:-dummybucket}"
ONEAPP_INFLUXDB_HOST="127.0.0.1"
ONEAPP_INFLUXDB_PORT="8086"
if [[ "${ONEAPP_INFLUXDB_VERSION}" == 2* ]]; then
  VERSION_TYPE="v2"
else
  VERSION_TYPE="v1"
fi
LOCAL_BIN_PATH="/usr/local/bin"
INFLUXDB_SERVER_BIN="${LOCAL_BIN_PATH}/influxd"
INFLUXDB_CLIENT_BIN="${LOCAL_BIN_PATH}/influx"

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
  install_influxdb_server

  install_influxdb_client

  systemctl daemon-reload

  # cleanup
  postinstall_cleanup

  msg info "INSTALLATION FINISHED"

  return 0
}

service_configure()
{
  export DEBIAN_FRONTEND=noninteractive

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

install_influxdb_server()
{
  msg info "Install InfluxDB ${VERSION_TYPE} server"
  if [[ "${VERSION_TYPE}" == "v1" ]]; then
    curl --location -O https://download.influxdata.com/influxdb/releases/influxdb-${ONEAPP_INFLUXDB_VERSION}_linux_amd64.tar.gz
    tar xvfz ./influxdb-${ONEAPP_INFLUXDB_VERSION}_linux_amd64.tar.gz
    rm -rf influxdb-${ONEAPP_INFLUXDB_VERSION}_linux_amd64.tar.gz
    cp influxdb-${ONEAPP_INFLUXDB_VERSION}/usr/bin/influxd ${LOCAL_BIN_PATH}
    cp influxdb-${ONEAPP_INFLUXDB_VERSION}/usr/bin/influx ${LOCAL_BIN_PATH}
    rm -rf influxdb-${ONEAPP_INFLUXDB_VERSION}
  else
    curl --location -O https://download.influxdata.com/influxdb/releases/influxdb2-${ONEAPP_INFLUXDB_VERSION}_linux_amd64.tar.gz
    tar xvfz ./influxdb2-${ONEAPP_INFLUXDB_VERSION}_linux_amd64.tar.gz
    rm -rf influxdb2-${ONEAPP_INFLUXDB_VERSION}_linux_amd64.tar.gz
    cp influxdb2-${ONEAPP_INFLUXDB_VERSION}/usr/bin/influxd ${LOCAL_BIN_PATH}
    rm -rf influxdb2-${ONEAPP_INFLUXDB_VERSION}
  fi
  msg info "Create service for InfluxDB"
  cat > /etc/systemd/system/influxd.service << EOF
[Unit]
Description=InfluxDB server
After=network.target

[Service]
Type=simple
ExecStart=${INFLUXDB_SERVER_BIN}
Restart=always
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

  systemctl enable --now influxdb.service
}

install_influxdb_client()
{
  msg info "Install InfluxDB ${VERSION_TYPE} client"
  if [[ "${VERSION_TYPE}" == "v2" ]]; then
    wget -P influxdb2-client-latest https://dl.influxdata.com/influxdb/releases/influxdb2-client-latest-linux-amd64.tar.gz
    tar xvzf ./influxdb2-client-latest/influxdb2-client-latest-linux-amd64.tar.gz -C influxdb2-client-latest
    cp influxdb2-client-latest/influx ${LOCAL_BIN_PATH}
    rm -rf influxdb2-client-latest
  fi
}

configure_influxdb()
{
  msg info "Configure InfluxDB ${VERSION_TYPE}"
  if [[ "${VERSION_TYPE}" == "v1" ]]; then
    ${INFLUXDB_CLIENT_BIN} -host http://${ONEAPP_INFLUXDB_HOST}:${ONEAPP_INFLUXDB_PORT} -execute "CREATE DATABASE ${ONEAPP_INFLUXDB_BUCKET}"
    ${INFLUXDB_CLIENT_BIN} -host http://${ONEAPP_INFLUXDB_HOST}:${ONEAPP_INFLUXDB_PORT} -execute "CREATE USER ${ONEAPP_INFLUXDB_USER} WITH PASSWORD '${ONEAPP_INFLUXDB_PASSWORD}' WITH ALL PRIVILEGES"
  else
    ${INFLUXDB_CLIENT_BIN} setup --host http://${ONEAPP_INFLUXDB_HOST}:${ONEAPP_INFLUXDB_PORT} \
    --org ${ONEAPP_INFLUXDB_ORG} \
    --bucket ${ONEAPP_INFLUXDB_BUCKET} \
    --username ${ONEAPP_INFLUXDB_USER} \
    --password ${ONEAPP_INFLUXDB_PASSWORD} \
    --token ${ONEAPP_INFLUXDB_TOKEN} \
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

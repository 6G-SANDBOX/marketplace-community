#!/usr/bin/env bash

set -o errexit -o pipefail

# ------------------------------------------------------------------------------
# Global variables
# ------------------------------------------------------------------------------

ONE_SERVICE_RECONFIGURABLE=false

ONEAPP_PROMETHEUS_VERSION="${ONEAPP_PROMETHEUS_VERSION:-2.53.4}"

ARCH="$(dpkg --print-architecture)"
PROMETHEUS_HOST="0.0.0.0"
PROMETHEUS_PORT="9090"
LOCAL_BIN_PATH="/usr/local/bin"
PROMETHEUS_BIN="${LOCAL_BIN_PATH}/prometheus"
PROMTOOL_BIN="${LOCAL_BIN_PATH}/promtool"
PROMETHEUS_ETC="/etc/prometheus"
PROMETHEUS_CONFIG_FILE="${PROMETHEUS_ETC}/prometheus.yml"

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

  # prometheus
  install_prometheus

  systemctl daemon-reload

  systemctl enable --now prometheus.service

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

install_prometheus() {
  msg info "Install Prometheus ${ONEAPP_PROMETHEUS_VERSION}"
  wget "https://github.com/prometheus/prometheus/releases/download/v${ONEAPP_PROMETHEUS_VERSION}/prometheus-${ONEAPP_PROMETHEUS_VERSION}.linux-${ARCH}.tar.gz"
  tar xzf "prometheus-${ONEAPP_PROMETHEUS_VERSION}.linux-${ARCH}.tar.gz"
  rm -rf "prometheus-${ONEAPP_PROMETHEUS_VERSION}.linux-${ARCH}.tar.gz"
  msg info "Copying Prometheus and Promtool to ${LOCAL_BIN_PATH}"
  EXTRACTED_DIR=$(find . -maxdepth 1 -type d -name 'prometheus-*' | head -n 1)
  cp "${EXTRACTED_DIR}/prometheus" ${LOCAL_BIN_PATH}
  cp "${EXTRACTED_DIR}/promtool" ${LOCAL_BIN_PATH}
  mkdir -p ${PROMETHEUS_ETC}
  cp "${EXTRACTED_DIR}/prometheus.yml" ${PROMETHEUS_CONFIG_FILE}
  rm -rf "${EXTRACTED_DIR}"
  msg info "Create service for Prometheus"
  cat > /etc/systemd/system/prometheus.service <<EOF
[Unit]
Description=Prometheus
After=network.target

[Service]
Type=simple
ExecStart=${PROMETHEUS_BIN} --config.file=${PROMETHEUS_CONFIG_FILE} --web.listen-address="${PROMETHEUS_HOST}:${PROMETHEUS_PORT}"
Restart=always

[Install]
WantedBy=multi-user.target
EOF

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

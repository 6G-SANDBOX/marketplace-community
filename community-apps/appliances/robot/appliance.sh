#!/usr/bin/env bash

set -o errexit -o pipefail

# ------------------------------------------------------------------------------
# Contextualization and global variables
# ------------------------------------------------------------------------------

#ONE_SERVICE_RECONFIGURABLE="false"

# ONEAPP_ROBOT_PUB_SSH_KEY="${ONEAPP_ROBOT_PUB_SSH_KEY:-}"
# ONEAPP_ROBOT_PRIV_SSH_KEY="${ONEAPP_ROBOT_PRIV_SSH_KEY:-}"

DEP_PKGS="iperf3 net-tools"
DOCKER_VERSION="5:26.1.3-1~ubuntu.22.04~jammy"
DOCKER_ROBOT_IMAGE="${REGISTRY_BASE_URL}/robot-tests-image"
DOCKER_ROBOT_IMAGE_VERSION="1.0"
REGISTRY_BASE_URL="example.com:5050/one/robot-tests"
VARIABLES_FILE="${BASE_DIR}/variables.sh"
BASE_DIR=/etc/one-appliance/service.d
CERTS_FOLDER="${BASE_DIR}/tests/certs"
IPERF3_PORT=5000


# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# Mandatory Functions
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------

service_install()
{
    export DEBIAN_FRONTEND=noninteractive
    systemctl stop unattended-upgrades

    install_pkg_deps

    install_docker

    build_docker_image

    postinstall_cleanup

    msg info "INSTALLATION FINISHED"

    return 0
}

service_configure()
{
    export DEBIAN_FRONTEND=noninteractive

    setup_environment

    create_certificates

    return 0
}

service_bootstrap()
{
    export DEBIAN_FRONTEND=noninteractive

    msg info "Run iperf server"
    run_iperf_server

    # msg info "Run Basic test"
    # run_basic_test

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

    msg info "Install required .deb packages"
    wait_for_dpkg_lock_release
    if ! apt-get install -y ${DEP_PKGS} ; then
        msg error "Package(s) installation failed"
        exit 1
    fi

    msg info "Download yq binary"
    if ! wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq ; then
        msg error "yq binary download failed"
        exit 1
    fi
    chmod +x /usr/bin/yq
}

install_docker()
{
    msg info "Add Docker official GPG key"
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    msg info "Add Docker repository to apt sources"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update

    msg info "Install Docker Engine"
    if ! apt-get install -y docker-ce=${DOCKER_VERSION} docker-ce-cli=${DOCKER_VERSION} containerd.io docker-buildx-plugin docker-compose-plugin ; then
        msg error "Docker installation failed"
        exit 1
    fi
}

build_docker_image()
{
    msg info "Build docker image for Robot Framework"
    docker build --no-cache -t "${DOCKER_ROBOT_IMAGE}":"${DOCKER_ROBOT_IMAGE_VERSION}" -f "${BASE_DIR}/tools/robot/Dockerfile" "${BASE_DIR}/tools/robot"
}


setup_environment()
{
    msg info "Setup Robot Framework environment"
    sed -i "s|^export REGISTRY_BASE_URL=.*|export REGISTRY_BASE_URL=\"${REGISTRY_BASE_URL}\"|" "${VARIABLES_FILE}"
    sed -i "s|^export DOCKER_ROBOT_IMAGE=.*|export DOCKER_ROBOT_IMAGE=${DOCKER_ROBOT_IMAGE}|" "${VARIABLES_FILE}"
    sed -i "s|^export DOCKER_ROBOT_IMAGE_VERSION=.*|export DOCKER_ROBOT_IMAGE_VERSION=${DOCKER_ROBOT_IMAGE_VERSION}|" "${VARIABLES_FILE}"
}

create_certificates()
{
    # id_rsa
    msg info "Create folder for certificates: ${CERTS_FOLDER}"
    mkdir -p ${CERTS_FOLDER}

    if [[ -z "${ONEAPP_ROBOT_PUB_SSH_KEY}" ]] || [[ -z "${ONEAPP_ROBOT_PRIV_SSH_KEY}" ]]; then
        msg info "Autogenerating certificates..."
        ssh-keygen -t ed25519 -C "$(hostname)" -f ${CERTS_FOLDER}/id_rsa -b 4096 -N ""
        onegate vm update --data ONEAPP_ROBOT_PUB_SSH_KEY="$(cat ${CERTS_FOLDER}/id_rsa.pub)"
    else
        msg info "Configuring provided certificates..."
        echo "${ONEAPP_ROBOT_PUB_SSH_KEY}" | base64 --decode >> "${CERTS_FOLDER}/id_rsa.pub"
        echo "${ONEAPP_ROBOT_PRIV_SSH_KEY}" | base64 --decode >> "${CERTS_FOLDER}/id_rsa"
    fi
}


run_iperf_server()
{
    msg info "Run iperf server"
    iperf3 -s -f M -D -I -p ${IPERF3_PORT}
}

run_basic_test()
{
    msg info "Run basic tests"
    DOCKER_ROBOT_TTY_OPTIONS="" ${BASE_DIR}/run_robot_tests.sh --include example
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

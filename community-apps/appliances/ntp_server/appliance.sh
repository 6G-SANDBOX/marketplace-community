#!/usr/bin/env bash

# ---------------------------------------------------------------------------- #
# Licensed under the Apache License, Version 2.0 (the "License"); you may      #
# not use this file except in compliance with the License. You may obtain      #
# a copy of the License at                                                     #
#                                                                              #
# http://www.apache.org/licenses/LICENSE-2.0                                   #
#                                                                              #
# Unless required by applicable law or agreed to in writing, software          #
# distributed under the License is distributed on an "AS IS" BASIS,            #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.     #
# See the License for the specific language governing permissions and          #
# limitations under the License.                                               #
# ---------------------------------------------------------------------------- #

set -o errexit -o pipefail

# ------------------------------------------------------------------------------
# Contextualization and global variables
# ------------------------------------------------------------------------------

ONEAPP_NTP_SERVERS="${ONEAPP_NTP_SERVERS:-0.es.pool.ntp.org,1.es.pool.ntp.org,2.es.pool.ntp.org,3.es.pool.ntp.org}"
ONEAPP_NTP_TZ="${ONEAPP_NTP_TZ:-Europe/Madrid}"

DOCKER_VERSION="5:26.1.3-1~ubuntu.22.04~jammy"


# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# Mandatory Functions
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------

service_install()
{
    export DEBIAN_FRONTEND=noninteractive
    systemctl stop unattended-upgrades

    # docker
    install_docker

    # cleanup
    postinstall_cleanup

    msg info "INSTALLATION FINISHED"

    return 0
}

service_configure()
{
    export DEBIAN_FRONTEND=noninteractive
    
    # Run docker container
    run_ntp_server

    msg info "CONFIGURE FINISHED"
    return 0
}

service_bootstrap()
{
    return 0
}


# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# Function Definitions
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------

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

run_ntp_server()
{
    docker rm -f ntp
    docker pull cturra/ntp
    docker run -tid --name=ntp --restart=always --publish=123:123/udp --env=NTP_SERVERS="$ONEAPP_NTP_SERVERS" --env=TZ="$ONEAPP_NTP_TZ" cturra/ntp
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

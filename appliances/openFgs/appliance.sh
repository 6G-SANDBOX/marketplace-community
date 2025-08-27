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
# Global variables
# ------------------------------------------------------------------------------

OPEN5GS_VERSION="2.7.6" 


# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# Mandatory Functions
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------

service_install()
{
    export DEBIAN_FRONTEND=noninteractive
    systemctl stop unattended-upgrades

    # install
    install_dependencies
    install_open5gs

    # cleanup
    postinstall_cleanup

    msg info "INSTALLATION FINISHED"

    return 0
}

service_configure()
{
    export DEBIAN_FRONTEND=noninteractive

    msg info "CONFIGURE FINISHED - now use ansible to configure the open5gs"
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

install_dependencies()
{
    msg info "update apt"
    apt-get update

    msg info "Install dependencies"
    if ! apt-get install -y bmon tmux jq ; then
        msg error "installation failed"
        exit 1
    fi

    msg info "Adding MongoDB 6 PPA | no apt key"
    mkdir -p /etc/apt/keyrings
    if ! (curl -fsSL https://www.mongodb.org/static/pgp/server-6.0.asc | sudo tee /etc/apt/keyrings/mongodb-server-6.0.asc); then
        msg error "adding MongoDB 6 PPA no apt key failed"
        exit 1
    fi

    msg info "Adding MongoDB 6 | apt source"
    if ! (echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/mongodb-server-6.0.asc] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-6.0.list) ; then
        msg error "adding MongoDB 6 PPA apt sourcefailed"
        exit 1
    fi

    msg info "Installing mongodb-org"
    apt-get update
    if ! apt install -y mongodb-org ; then
        msg error "mongodb-org installation failed"
        exit 1
    fi
}


install_open5gs()
{
    msg info "Install open5gs"
    msg info "Adding Open5GS PPA..."
    if ! add-apt-repository -y ppa:open5gs/latest ; then
        msg error "adding Open5GS PPA failed"
        exit 1
    fi

    msg info "Installing open5gs ${OPEN5GS_VERSION}~*..."
    if ! apt-get install -y open5gs=${OPEN5GS_VERSION}~* ; then
        msg error "open5gs installation failed"
        exit 1
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

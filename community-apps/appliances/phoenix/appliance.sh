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

DEPLOY_TOKEN=''
DOWNLOAD_URL=''


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
    install_o5gc

    # cleanup
    postinstall_cleanup

    msg info "INSTALLATION FINISHED"

    return 0
}

service_configure()
{
    export DEBIAN_FRONTEND=noninteractive

    msg info "CONFIGURE FINISHED - now use ansible to configure the open5gcore"
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

    msg info "Install mariadb"
    if ! apt-get install -y mariadb-server ; then
        msg error "installation failed"
        exit 1
    fi

    msg info "Install dependencies"
    if ! apt-get install -y bmon tmux jq ; then
        msg error "installation failed"
        exit 1
    fi
}

install_o5gc()
{
    msg info "downloading deb file"

    if [ -z "$DOWNLOAD_URL"  ] || [ -z "${DEPLOY_TOKEN}" ] ; then
        msg error "Download failed: DOWNLOAD_URL and DEPLOY_TOKEN needed!"
        exit 1
    fi

    if ! wget --no-verbose --password="${DEPLOY_TOKEN}" --user=token "$DOWNLOAD_URL" -O /root/phoenix.deb ; then
        msg error "Download failed"
        exit 1
    fi

    msg info "Install open5gcore deb"
    if ! apt-get install -y /root/phoenix.deb ; then
        msg error "installation failed"
        exit 1
    fi
}


postinstall_cleanup()
{
    msg info "Delete cache and stored packages"
    apt-get autoclean
    apt-get autoremove
    rm -rf /var/lib/apt/lists/*
    rm -rf /root/phoenix.deb
}


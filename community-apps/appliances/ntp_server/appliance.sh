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


# List of contextualization parameters
ONE_SERVICE_PARAMS=(
    'ONEAPP_NTP_SERVERS'            'configure'  'List of NTP Servers to use as Upstream'                                      'O|text'
    'ONEAPP_NTP_TZ'                 'configure'  'Timezone defined by IANAA https://ftp.iana.org/tz/tzdb-2020f/zone1970.tab'   'O|text'
)


### Appliance metadata ###############################################

# Appliance metadata
ONE_SERVICE_NAME='Service NTP SERVER - KVM'
ONE_SERVICE_VERSION='0.0.1'   #latest
ONE_SERVICE_BUILD=$(date +%s)
ONE_SERVICE_SHORT_DESCRIPTION='Appliance with a NTP SERVER'
ONE_SERVICE_DESCRIPTION=$(cat <<EOF
Appliance with preinstalled NTP Server based on Chrony and Docker.

See the dedicated [documentation](https://hub.docker.com/r/cturra/ntp).

The ONEAPP_NTP_SERVERS and ONEAPP_NTP_TZ parameters are optinally configurable:
- ONEAPP_NTP_SERVERS is the list of NTP servers that you want to use as Upstream servers.
- ONEAPP_NTP_TZ is the timezone defined by IANAA.
EOF
)

ONE_SERVICE_RECONFIGURABLE=true

### Contextualization defaults #######################################

ONEAPP_NTP_SERVERS="${ONEAPP_NTP_SERVERS:-0.es.pool.ntp.org,1.es.pool.ntp.org,2.es.pool.ntp.org,3.es.pool.ntp.org}"
ONEAPP_NTP_TZ="${ONEAPP_NTP_TZ:-Europe/Madrid}"

### Globals ##########################################################

DOCKER_VERSION="5:26.1.3-1~ubuntu.22.04~jammy"

###############################################################################
###############################################################################
###############################################################################

#
# service implementation
#

service_install()
{
    export DEBIAN_FRONTEND=noninteractive
    systemctl stop unattended-upgrades

    # docker
    install_docker

    # service metadata
    create_one_service_metadata

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

###############################################################################
###############################################################################
###############################################################################

#
# functions
#
install_docker()
{
    msg info "Add Docker official GPG key"
    install -m 0755 -d /etc/apt/keyrings

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc

    chmod a+r /etc/apt/keyrings/docker.asc

    msg info "Add Docker repository to apt sources"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update

    msg info "Install Docker Engine"
    if ! apt-get install -y docker-ce=$DOCKER_VERSION docker-ce-cli=$DOCKER_VERSION containerd.io docker-buildx-plugin docker-compose-plugin ; then
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

postinstall_cleanup()
{
    msg info "Delete cache and stored packages"
    apt-get autoclean
    apt-get autoremove
    rm -rf /var/lib/apt/lists/*
}


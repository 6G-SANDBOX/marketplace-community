#!/usr/bin/env bash

set -o errexit -o pipefail

# ------------------------------------------------------------------------------
# Appliance metadata
# ------------------------------------------------------------------------------

ONE_SERVICE_NAME='6G-Sandbox bastion'
ONE_SERVICE_VERSION='v0.3.0'   #latest
ONE_SERVICE_BUILD=$(date +%s)
ONE_SERVICE_SHORT_DESCRIPTION='6G-Sandbox bastion appliance for KVM'
ONE_SERVICE_DESCRIPTION=$(cat <<EOF
This appliance installs the latest version of the bastion, the entrypoint of every Virtual Network, with additional services such as:
- Technitium DNS
- [route-manager-api](https://github.com/6G-SANDBOX/route-manager-api)
- Wireguard VPN

The Bastion has IPv4 routing enabled by default, with all private IPs forbidden by default, unless explictly specified.

The image is based on an Ubuntu 22.04 cloud image with the OpenNebula [contextualization package](http://docs.opennebula.io/6.6/management_and_operations/references/kvm_contextualization.html).

After deploying the appliance, check the status of the deployment in /etc/one-appliance/status. You chan check the appliance logs in /var/log/one-appliance/.
EOF
)

ONE_SERVICE_RECONFIGURABLE=false


# ------------------------------------------------------------------------------
# List of contextualization parameters
# ------------------------------------------------------------------------------

ONE_SERVICE_PARAMS=(
    'ONEAPP_BASTION_DNS_PASSWORD'             'configure'  'For the Technitium DNS, admin user password.'                     'O|password'
    'ONEAPP_BASTION_DNS_FORWARDERS'           'configure'  'For the Technitium DNS, comma separated list of forwarders to be used by the DNS server.'    'O|text'
    'ONEAPP_BASTION_DNS_DOMAIN'               'configure'  'For the Technitium DNS, domain name for creating the new zone.'   'M|text'
    'ONEAPP_BASTION_ROUTEMANAGER_TOKEN'       'configure'  'For the route-manager-api, token to authenticate to the API. If not provided, a new one will be generated at instanciate time with `openssl rand -base64 32`.' 'O|password'
    'ONEAPP_BASTION_ROUTEMANAGER_PORT'        'configure'  'TCP port where the route-manager-api service will be exposed.'    'O|text'
)

ONEAPP_BASTION_DNS_PASSWORD="${ONEAPP_BASTION_DNS_PASSWORD:-admin}"
ONEAPP_BASTION_DNS_FORWARDERS="${ONEAPP_BASTION_DNS_FORWARDERS:-'8.8.8.8, 1.1.1.1'}"
ONEAPP_BASTION_ROUTEMANAGER_PORT="${ONEAPP_ROUTEMANAGER_PORT:-8172}"


# ------------------------------------------------------------------------------
# Global variables
# ------------------------------------------------------------------------------

DEP_PKGS="git python3 wireguard"

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

    # Technitium DNS
    install_dns

    # route-manager-api
    install_routemanager

    # service metadata
    create_one_service_metadata

    # cleanup
    postinstall_cleanup

    msg info "INSTALLATION FINISHED"

    return 0
}

# Runs when VM is first started, and every time 
service_configure()
{

    # Technitium DNS
    configure_dns

    # route-manager-api
    configure_routemanager

    msg info "CONFIGURATION FINISHED"
    return 0
}

service_bootstrap()
{
    msg info "BOOTSTRAP FINISHED"
    return 0
}

# This one is not really mandatory, however it is a handled function
service_help()
{
    msg info "Example appliance how to use message. If missing it will default to the generic help"

    return 0
}

# This one is not really mandatory, however it is a handled function
service_cleanup()
{
    msg info "CLEANUP logic goes here in case of install failure"
    :
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

    msg info "Install required packages for ${ONE_SERVICE_NAME}"
    wait_for_dpkg_lock_release
    if ! apt-get install -y "${DEP_PKGS}" ; then
        msg error "Package(s) installation failed"
        exit 1
    fi
}

install_dns()
{
    # Install Technitium DNS
    if ! curl -sSL https://download.technitium.com/dns/install.sh | sudo bash; then
        msg error "Technitium DNS install script encountered an error"
        exit 1
    fi
}

configure_dns()
{  
    # first login
    msg info "First login into Technitium DNS API"
    tmp_token=$(api_request "/user/login?user=admin&pass=admin&includeInfo=false" | jq -r '.token')

    # persistent token
    msg info "Set persistent login for DNS user 'admin'"
    token=$(api_request "/user/createToken?user=admin&pass=admin&tokenName=JenkinsToken" | jq -r '.token')

    # change password
    if [[ -z "${ONEAPP_BASTION_DNS_PASSWORD}" || "${ONEAPP_BASTION_DNS_PASSWORD}" == "admin" ]]; then
        msg info "Default password for DNS user 'admin' will remain as-is"
    else
        msg info "Change default password for DNS user 'admin'"
        api_request "/user/changePassword?token=${tmp_token}&pass=${ONEAPP_BASTION_DNS_PASSWORD}"
    fi

    # logout first login
    msg info "Logout from first login"
    api_request "/user/logout?token=${tmp_token}" | jq -r '.token'

    # DNS domain and forwarders
    msg info "Set DNS domain and forwarders"
    api_request "/settings/set?token=${token}&dnsServerDomain=${ONEAPP_BASTION_DNS_DOMAIN}&forwarders=${ONEAPP_BASTION_DNS_FORWARDERS}"

    # DNS zone
    msg info "Set DNS zone where new entries will be set"
    api_request "/zones/create?token=${token}&zone=${ONEAPP_BASTION_DNS_DOMAIN}&type=Primary"

    # download request logs plugin
    msg info "Download Query Logs plugin to Technitium DNS"
    api_request "/apps/downloadAndInstall?token=${token}&name=Query Logs (Sqlite)&url=https://download.technitium.com/dns/apps/QueryLogsSqliteApp-v6.zip"
}

dns_api()
{
    base_url="http://localhost:5380/api"
    local endpoint=$1

    response=$(curl -s -w "%{http_code}" --location "${base_url}${endpoint}")
    [[ "${response: -3}" != "200" ]] && msg error "HTTP error: $(echo "${response::-3}" | jq)" && exit 1
    [[ "$(echo "${response::-3}" | jq -r '.status')" != "ok" ]] && msg error "API error: $(echo "${response::-3}" | jq -r '.errorMessage')" && exit 1
    echo "${response::-3}"
}


install_routemanager()
{
    msg info "git clone route-manager-api repository"
    if ! git clone https://github.com/6G-SANDBOX/route-manager-api /opt/route-manager-api ; then
        msg error "Error cloning route-manager-api repository"
        exit 1
    fi

    msg info "Create and activate venv 'routemgr'"
    python3 -m venv /opt/route-manager-api/routemgr
    source /opt/route-manager-api/routemgr/bin/activate

    msg info "install application requirements inside the 'routemgr' venv"
    if ! pip install -r /opt/route-manager-api/requirements.txt ; then
        msg error "Error downloading required python packages"
        exit 1
    fi
    deactivate


    routemanager_service

}

routemanager_service()
{
    msg info "Define route-manager-api systemd service"
    cat > /etc/systemd/system/route-manager-api.service << 'EOF'
[Unit]
Description=A REST API developed with FastAPI for managing network routes on a Linux machine using the ip command. It allows you to query active routes, create new routes, and delete existing routes, with token-based authentication and persistence of scheduled routes to ensure their availability even after service restarts.
After=network.target

[Service]
Type=simple
ExecStart=/opt/route-manager-api/routemgr/bin/python3 /opt/route-manager-api/main.py
StandardOutput=append:/var/log/route_manager.log
StandardError=append:/var/log/route_manager.log
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    chmod +x /etc/systemd/system/route-manager-api.service
    
    msg info "Enable route-manager-api systemd service"
    if ! systemctl enable route-manager-api.service ; then
        msg error "Service route-manager-api could not be enabled succesfully"
        exit 1
    fi
}

configure_routemanager()
{
    if [[ -z "${ONEAPP_BASTION_ROUTEMANAGER_TOKEN}" ]] ; then
        msg info "TOKEN for route-manager-api not provided. Generating one"
        ONEAPP_BASTION_ROUTEMANAGER_TOKEN=$(openssl rand -base64 32)
        onegate vm update --data ONEAPP_BASTION_ROUTEMANAGER_TOKEN="${ONEAPP_BASTION_ROUTEMANAGER_TOKEN}"
    fi

    msg info "Update APITOKEN for route-manager-api config file"
    sed -i "s%^APITOKEN = .*%APITOKEN = ${ONEAPP_BASTION_ROUTEMANAGER_TOKEN}%" /opt/route-manager-api/config/config.conf
    sed -i "s%^PORT = .*%PORT = ${ONEAPP_BASTION_ROUTEMANAGER_PORT}%" /opt/route-manager-api/config/config.conf

    msg info "Restart service route-manager-api"
    if ! systemctl restart route-manager-api.service ; then
        msg error "Error restarting service route-manager-api"
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
    echo "Could not get lock ${lock_file} due to unattended-upgrades. Retrying in ${interval} seconds..."
    sleep "${interval}"
  done

  echo "Error: 10m timeout without ${lock_file} being released by unattended-upgrades"
  exit 1
}

postinstall_cleanup()
{
    msg info "Delete cache and stored packages"
    apk cache clean
    apk del --purge
    rm -rf /var/cache/apk/*
}
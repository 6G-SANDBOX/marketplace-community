#!/usr/bin/env bash

set -o errexit -o pipefail

# ------------------------------------------------------------------------------
# Contextualization and global variables
# ------------------------------------------------------------------------------

ONEAPP_BASTION_DNS_FORWARDERS="${ONEAPP_BASTION_DNS_FORWARDERS:-'8.8.8.8,1.1.1.1'}"

DEP_PKGS="git wireguard"


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

    # route-manager-api
    install_routemanager

    # Technitium DNS
    install_dns

    # cleanup
    postinstall_cleanup

    msg info "INSTALLATION FINISHED"

    return 0
}

service_configure()
{
    export DEBIAN_FRONTEND=noninteractive

    # Technitium DNS
    configure_dns

    # route-manager-api
    configure_routemanager

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

    msg info "Install required .deb packages"
    wait_for_dpkg_lock_release
    if ! apt-get install -y ${DEP_PKGS} ; then
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

    # Wait 5 seconds for Technitium DNS API to start
    sleep 5

    # temporal login
    msg info "Temporal login into Technitium DNS API"
    tmp_token=$(dns_api "/user/login?user=admin&pass=admin&includeInfo=false" | jq -r '.token')

    # download request logs plugin
    msg info "Download Query Logs plugin to Technitium DNS"
    dns_api "/apps/downloadAndInstall?token=${tmp_token}&name=Query%20Logs%20%28Sqlite%29&url=https://download.technitium.com/dns/apps/QueryLogsSqliteApp-v6.zip" 1>/dev/null

    # logout temporal login
    msg info "Logout from temporal login"
    dns_api "/user/logout?token=${tmp_token}" 1>/dev/null
}

configure_dns()
{  
    # temporal login
    msg info "Temporal login into Technitium DNS API"
    tmp_token=$(dns_api "/user/login?user=admin&pass=admin&includeInfo=false" | jq -r '.token')

    # persistent token
    msg info "Set persistent login for DNS user 'admin'"
    token=$(dns_api "/user/createToken?user=admin&pass=admin&tokenName=JenkinsToken" | jq -r '.token')
    onegate vm update --data ONEAPP_BASTION_DNS_TOKEN="${token}"

    if [[ -z "${ONEAPP_BASTION_DNS_PASSWORD}" ]] ; then
        msg info "Password for Technitium DNS's admin user not provided. Generating one"
        ONEAPP_BASTION_DNS_PASSWORD=$(openssl rand -base64 32 | tr '/+' '_-')
        onegate vm update --data ONEAPP_BASTION_DNS_PASSWORD="${ONEAPP_BASTION_DNS_PASSWORD}"
    fi

    # change password
    msg info "Change default password for DNS user 'admin'"
    dns_api "/user/changePassword?token=${tmp_token}&pass=${ONEAPP_BASTION_DNS_PASSWORD}" 1>/dev/null

    # logout temporal login
    msg info "Logout from temporal login"
    dns_api "/user/logout?token=${tmp_token}" 1>/dev/null

    # DNS domain and forwarders
    msg info "Set DNS domain and forwarders"
    dns_api "/settings/set?token=${token}&dnsServerDomain=$(hostname | rev | cut -d'-' -f1 | rev).${ONEAPP_BASTION_DNS_DOMAIN}&dnsServerLocalEndPoints=127.0.0.1:53,[::]:53&forwarders=$(echo "${ONEAPP_BASTION_DNS_FORWARDERS}" | tr -d ' ')" 1>/dev/null


    # DNS zone
    msg info "Set DNS zone where new entries will be set"
    dns_api "/zones/create?token=${token}&zone=${ONEAPP_BASTION_DNS_DOMAIN}&type=Primary" 1>/dev/null
}

dns_api()
{
    base_url="http://localhost:5380/api"
    local endpoint=$1

    response=$(curl -s -w "%{http_code}" --location "${base_url}${endpoint}")

    http_code="${response: -3}"
    body="${response::-3}"

    # Verify http_code is 200
    if [[ "$http_code" != "200" ]]; then
        msg error "API returned code ${http_code}:${body})"
        exit 1
    fi

    # Verify response is a valid JSON
    if ! echo "${body}" | jq empty > /dev/null 2>&1; then
        msg error "Invalid response received from API: ${body}"
        exit 1
    fi

    # Verify response has ok status
    if [[ "$(echo "${body}" | jq -r '.status')" != "ok" ]]; then
        msg error "API returned error: $(echo "${body}" | jq -r '.errorMessage')"
        exit 1
    fi
    echo "${body}"
}


install_routemanager()
{
    msg info "git clone route-manager-api repository"
    if ! git clone https://github.com/6G-SANDBOX/route-manager-api /opt/route-manager-api ; then
        msg error "Error cloning route-manager-api repository"
        exit 1
    fi

    msg info "Install uv"
    if ! (curl -LsSf https://astral.sh/uv/install.sh | sh); then
        msg error "Error installing uv"
        exit 1
    fi

    msg info "Create virtual environment"
    if ! (/root/.local/bin/uv sync --project /opt/route-manager-api/); then
        msg error "Error creating .venv"
        exit 1
    fi

    routemanager_service

    msg info "Enable ipv4 forwarding"
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-ipv4-ip_forward.conf

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
User=root
Group=root
ExecStart=/root/.local/bin/uv --directory /opt/route-manager-api/ run fastapi run --port 8172
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
    TEMP="$(onegate vm show --json |jq -r .VM.USER_TEMPLATE.ONEAPP_BASTION_ROUTEMANAGER_APITOKEN)"

    if [[ -z "${ONEAPP_BASTION_ROUTEMANAGER_APITOKEN}" && "${TEMP}" == null ]] ; then
        msg info "APITOKEN for route-manager-api not provided. Generating one"
        ONEAPP_BASTION_ROUTEMANAGER_APITOKEN=$(openssl rand -base64 32)
        onegate vm update --data ONEAPP_BASTION_ROUTEMANAGER_APITOKEN="${ONEAPP_BASTION_ROUTEMANAGER_APITOKEN}"
    elif [[ "${TEMP}" != null ]] ; then
        msg info "Using provided or previously generated APITOKEN"
        ONEAPP_BASTION_ROUTEMANAGER_APITOKEN="${TEMP}"
    fi

    msg info "Update APITOKEN for route-manager-api config file"
    sed -i "s%^APITOKEN = .*%APITOKEN = ${ONEAPP_BASTION_ROUTEMANAGER_APITOKEN}%" /opt/route-manager-api/.env

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
    msg info "Could not get lock ${lock_file} due to unattended-upgrades. Retrying in ${interval} seconds..."
    sleep "${interval}"
  done

  msg error "Error: 10m timeout without ${lock_file} being released by unattended-upgrades"
  exit 1
}

postinstall_cleanup()
{
    msg info "Delete cache and stored packages"
    apt-get autoclean
    apt-get autoremove
    rm -rf /var/lib/apt/lists/*
}
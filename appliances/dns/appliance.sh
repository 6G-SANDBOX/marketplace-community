#!/usr/bin/env bash

set -o errexit -o pipefail

# ------------------------------------------------------------------------------
# Contextualization and global variables
# ------------------------------------------------------------------------------

ONEAPP_DNS_FORWARDERS="${ONEAPP_DNS_FORWARDERS:-'8.8.8.8,1.1.1.1'}"


# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# Mandatory Functions
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------

service_install()
{
    export DEBIAN_FRONTEND=noninteractive

    # Technitium DNS
    install_dns

    # cleanup
    postinstall_cleanup

    msg info "INSTALLATION FINISHED"

    return 0
}

service_configure()
{
    # Technitium DNS
    configure_dns

    msg info "CONFIGURATION FINISHED"
    return 0
}

service_bootstrap()
{
    msg info "BOOTSTRAP FINISHED"
    return 0
}


# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# Function Definitions
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------

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
    onegate vm update --data ONEAPP_DNS_TOKEN="${token}"

    if [[ -z "${ONEAPP_DNS_PASSWORD}" ]] ; then
        msg info "Password for admin user not provided. Generating one"
        ONEAPP_DNS_PASSWORD=$(openssl rand -base64 32 | tr '/+' '_-')
        onegate vm update --data ONEAPP_DNS_PASSWORD="${ONEAPP_DNS_PASSWORD}"
    fi

    # change password
    msg info "Change default password for DNS user 'admin'"
    dns_api "/user/changePassword?token=${tmp_token}&pass=${ONEAPP_DNS_PASSWORD}" 1>/dev/null

    # logout temporal login
    msg info "Logout from temporal login"
    dns_api "/user/logout?token=${tmp_token}" 1>/dev/null

    # DNS domain and forwarders
    msg info "Set DNS domain and forwarders"
    dns_api "/settings/set?token=${token}&dnsServerDomain=ns.${ONEAPP_DNS_DOMAIN}&dnsServerLocalEndPoints=0.0.0.0:53,127.0.0.1:53,[::]:53&forwarders=$(echo "${ONEAPP_DNS_FORWARDERS}" | tr -d ' ')" 1>/dev/null

    # DNS zone
    msg info "Set DNS zone where new entries will be set"
    dns_api "/zones/create?token=${token}&zone=${ONEAPP_DNS_DOMAIN}&type=Primary" 1>/dev/null
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
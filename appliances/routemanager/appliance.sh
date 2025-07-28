#!/usr/bin/env bash

set -o errexit -o pipefail

# ------------------------------------------------------------------------------
# Contextualization and global variables
# ------------------------------------------------------------------------------

ONE_SERVICE_RECONFIGURABLE=true

DEP_PKGS="git"


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

    # clone
    clone_repo

    # venv
    create_venv

    # service
    routemanager_service

    # enable routing
    msg info "Enable ipv4 forwarding"
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-ipv4-ip_forward.conf

    # cleanup
    postinstall_cleanup

    msg info "INSTALLATION FINISHED"

    return 0
}

service_configure()
{
    export DEBIAN_FRONTEND=noninteractive

    # config
    configure_token

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

clone_repo()
{
    msg info "git clone route-manager-api repository"
    if ! git clone https://github.com/6G-SANDBOX/route-manager-api /opt/route-manager-api ; then
        msg error "Error cloning route-manager-api repository"
        exit 1
    fi
}

create_venv()
{
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
}

routemanager_service()
{
    msg info "Defining route-manager-api systemd service"
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

configure_token()
{
    TEMP="$(onegate vm show --json |jq -r .VM.USER_TEMPLATE.ONEAPP_ROUTEMANAGER_APITOKEN)"

    if [[ -z "${ONEAPP_ROUTEMANAGER_APITOKEN}" && "${TEMP}" == null ]] ; then
        msg info "APITOKEN for route-manager-api not provided. Generating one"
        ONEAPP_ROUTEMANAGER_APITOKEN=$(openssl rand -base64 32)
        onegate vm update --data ONEAPP_ROUTEMANAGER_APITOKEN="${ONEAPP_ROUTEMANAGER_APITOKEN}"

    elif [[ "${TEMP}" != null ]] ; then
        msg info "Using provided or previously generated APITOKEN"
        ONEAPP_ROUTEMANAGER_APITOKEN="${TEMP}"
    fi

    msg info "Update APITOKEN for route-manager-api config file"
    sed -i "s%^APITOKEN = .*%APITOKEN = ${ONEAPP_ROUTEMANAGER_APITOKEN}%" /opt/route-manager-api/.env

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
    wait_for_dpkg_lock_release
    apt-get autoclean
    apt-get autoremove
    rm -rf /var/lib/apt/lists/*
}

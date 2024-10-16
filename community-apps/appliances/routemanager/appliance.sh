#!/usr/bin/env bash

set -o errexit -o pipefail

# ------------------------------------------------------------------------------
# Appliance metadata
# ------------------------------------------------------------------------------

ONE_SERVICE_NAME='6G-Sandbox route-manager-api'
ONE_SERVICE_VERSION='v0.3.2'   #latest
ONE_SERVICE_BUILD=$(date +%s)
ONE_SERVICE_SHORT_DESCRIPTION='6G-Sandbox route-manager-api appliance for KVM'
ONE_SERVICE_DESCRIPTION=$(cat <<EOF
This appliance installs the latest version of [route-manager-api](https://github.com/6G-SANDBOX/route-manager-api), a REST API in port 8172/tcp developed with FastAPI for managing network routes on a Linux machine using the ip command.

The image is based on an Alpine 3.20 cloud image with the OpenNebula [contextualization package](http://docs.opennebula.io/6.6/management_and_operations/references/kvm_contextualization.html).

After deploying the appliance, check the status of the deployment in /etc/one-appliance/status. You chan check the appliance logs in /var/log/one-appliance/.
EOF
)

ONE_SERVICE_RECONFIGURABLE=true


# ------------------------------------------------------------------------------
# List of contextualization parameters
# ------------------------------------------------------------------------------

ONE_SERVICE_PARAMS=(
    'ONEAPP_ROUTEMANAGER_TOKEN'       'configure'  'Token to authenticate to the API. If not provided, a new one will be generated at instanciate time with `openssl rand -base64 32`' 'O|password'
    'ONEAPP_ROUTEMANAGER_PORT'        'configure'  'TCP port where the route-manager-api service will be exposed'    'O|text'
)

ONEAPP_ROUTEMANAGER_PORT="${ONEAPP_ROUTEMANAGER_PORT:-8172}"

# ------------------------------------------------------------------------------
# Global variables
# ------------------------------------------------------------------------------

DEP_PKGS="git python3"

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# Mandatory Functions
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------

service_install()
{

    # packages
    install_pkg_deps DEP_PKGS

    # clone
    clone_repo

    # venv
    create_venv

    # service
    define_service

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
    # TOKEN
    generate_token

    # config
    update_config

    msg info "CONFIGURATION FINISHED"
    return 0
}

service_bootstrap()
{
    if ! rc-service route-manager-api restart ; then
        msg error "Error restarting service route-manager-api"
        exit 1
    fi
    msg info "Service route-manager-api restarted"

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
    msg info "Run apk update"
    apk update

    msg info "Install required packages for route-manager-api"
    if ! apk add ${!1} ; then
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
    msg info "Create and activate venv 'routemgr'"
    python3 -m venv /opt/route-manager-api/routemgr
    source /opt/route-manager-api/routemgr/bin/activate

    msg info "install application requirements inside the venv"
    if ! pip install -r /opt/route-manager-api/requirements.txt ; then
        msg error "Error downloading required python packages"
        exit 1
    fi
    deactivate
}

define_service()
{
    msg info "Defining route-manager-api OpenRC service"
    cat > /etc/init.d/route-manager-api << 'EOF'
#!/sbin/openrc-run

name="route-manager-api"
description="A REST API developed with FastAPI for managing network routes on a Linux machine using the ip command. It allows you to query active routes, create new routes, and delete existing routes, with token-based authentication and persistence of scheduled routes to ensure their availability even after service restarts."
command="/opt/route-manager-api/routemgr/bin/python3"
command_args="/opt/route-manager-api/main.py"
command_background="yes"
pidfile="/var/run/route_manager.pid"

output_log="/var/log/route_manager.log"

depend() {
    after net
}

start_pre() {
    cd /opt/route-manager-api
}

start() {
    ebegin "Starting Route Manager"
    start-stop-daemon --start --background --make-pidfile --pidfile "${pidfile}" \
    --stdout "${output_log}" --stderr "${output_log}" --exec ${command} -- ${command_args}
    eend $?
}

EOF

    chmod +x /etc/init.d/route-manager-api
    
    msg info "Enabling service route-manager-api"
    if ! rc-update add route-manager-api default ; then
        msg error "Service route-manager-api could not be enabled succesfully"
        exit 1
    fi
}

generate_token()
{
    TEMP="$(onegate vm show --json |jq -r .VM.USER_TEMPLATE.ONEAPP_ROUTEMANAGER_TOKEN)"

    if [[ -z "${ONEAPP_ROUTEMANAGER_TOKEN}" && "${TEMP}" == null ]] ; then
        msg info "TOKEN not provided. Generating one"
        ONEAPP_ROUTEMANAGER_TOKEN=$(openssl rand -base64 32)
        onegate vm update --data ONEAPP_ROUTEMANAGER_TOKEN="${ONEAPP_ROUTEMANAGER_TOKEN}"

    elif [[ "${TEMP}" != null ]] ; then
        msg info "Using provided or previously generated TOKEN"
        ONEAPP_ROUTEMANAGER_TOKEN="${TEMP}"
    fi
}


update_config()
{
    msg info "Update application config file"
    sed -i "s%^TOKEN = .*%TOKEN = ${ONEAPP_ROUTEMANAGER_TOKEN}%" /opt/route-manager-api/config/config.conf
    sed -i "s%^PORT = .*%PORT = ${ONEAPP_ROUTEMANAGER_PORT}%" /opt/route-manager-api/config/config.conf
}

postinstall_cleanup()
{
    msg info "Delete cache and stored packages"
    apk cache clean
    apk del --purge
    rm -rf /var/cache/apk/*
}

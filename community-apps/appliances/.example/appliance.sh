#!/usr/bin/env bash

# This script contains an example implementation logic for your appliances.
# For this example the goal will be to have a "database as a service" appliance

set -o errexit -o pipefail

# ------------------------------------------------------------------------------
# Appliance metadata
# ------------------------------------------------------------------------------

# If your "service_install" function includes the "create_one_service_metadata" function
# The same metadata as in the marketplace yaml file will be placed in /etc/one-appliance/metadata inside the appliance
ONE_SERVICE_NAME='Service example - KVM'
ONE_SERVICE_VERSION=''   #latest
ONE_SERVICE_BUILD=$(date +%s)
ONE_SERVICE_SHORT_DESCRIPTION='Sample Appliance for KVM hosts'
ONE_SERVICE_DESCRIPTION=$(cat <<EOF
Sample Appliance for KVM hosts.

After deploying the appliance, check the status of the deployment in /etc/one-appliance/status. You chan check the appliance logs in /var/log/one-appliance/.
EOF
)

# Whether service_configure() and service_bootstrap() can run again
ONE_SERVICE_RECONFIGURABLE=true


# ------------------------------------------------------------------------------
# List of contextualization parameters
# ------------------------------------------------------------------------------

# This is how you interact with the appliance using OpenNebula.
# These variables are defined in the CONTEXT section of the VM Template as custom variables
# https://docs.opennebula.io/6.8/management_and_operations/references/template.html#context-section

# 'name' 'type' 'description' 'input'.
# 'type' is always 'configure', and 'input' are shown at https://docs.opennebula.io/6.8/management_and_operations/references/template.html#template-user-inputs
ONE_SERVICE_PARAMS=(
    'ONEAPP_LITHOPS_BACKEND'            'configure'  'Lithops compute backend'                                          'O|text'
    'ONEAPP_LITHOPS_STORAGE'            'configure'  'Lithops storage backend'                                          'O|text'
    'ONEAPP_MINIO_ENDPOINT'             'configure'  'Lithops storage backend MinIO endpoint URL'                       'O|text'
    'ONEAPP_MINIO_ACCESS_KEY_ID'        'configure'  'Lithops storage backend MinIO account user access key'            'O|text'
    'ONEAPP_MINIO_SECRET_ACCESS_KEY'    'configure'  'Lithops storage backend MinIO account user secret access key'     'O|text'
    'ONEAPP_MINIO_BUCKET'               'configure'  'Lithops storage backend MinIO existing bucket'                    'O|text'
    'ONEAPP_MINIO_ENDPOINT_CERT'        'configure'  'Lithops storage backend MinIO endpoint certificate'               'O|text64'
)

# Default values for when the variable isn't defined on the VM Template
ONEAPP_LITHOPS_BACKEND="${ONEAPP_LITHOPS_BACKEND:-localhost}"
ONEAPP_LITHOPS_STORAGE="${ONEAPP_LITHOPS_STORAGE:-localhost}"

# You can make these parameters a required step of the VM instantiation wizard by using the USER_INPUTS feature
# https://docs.opennebula.io/6.8/management_and_operations/references/template.html#template-user-inputs


# ------------------------------------------------------------------------------
# Global variables
# ------------------------------------------------------------------------------

# For organization purposes is good to define here variables that will be used by your bash logic
DEP_PKGS="python3-pip"
DEP_PIP="boto3"
LITHOPS_VERSION="3.4.0"
DOCKER_VERSION="5:26.1.3-1~ubuntu.22.04~jammy"



# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# Function Definitions
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------

# The following functions will be called by the appliance service manager at
# the  different stages of the appliance life cycles. They must exist
# https://github.com/OpenNebula/one-apps/wiki/apps_intro#appliance-life-cycle

service_install()
{
    export DEBIAN_FRONTEND=noninteractive
    systemctl stop unattended-upgrades

    # packages
    install_deps DEP_PKGS DEP_PIP

    # docker
    install_docker

    # whatever your appliance is about
    install_whatever

    # create Lithops config file in /etc/lithops
    create_lithops_config

    # service metadata. Function defined at one-apps/appliances/lib/common.sh
    create_one_service_metadata

    # cleanup
    postinstall_cleanup

    msg info "INSTALLATION FINISHED"

    return 0
}

# Runs when VM is first started, and every time 
service_configure()
{
    export DEBIAN_FRONTEND=noninteractive

    # update Lithops config file if non-default options are set
    configure_something

    local_ca_folder="/usr/local/share/ca-certificates/minio"
    if [[ ! -z "${ONEAPP_MINIO_ENDPOINT_CERT}" ]] && [[ ! -f "${local_ca_folder}/ca.crt" ]]; then
        msg info "Adding trust CA for MinIO endpoint"

        if [[ ! -d "${local_ca_folder}" ]]; then
            msg info "Create folder ${local_ca_folder}"
            mkdir "${local_ca_folder}"
        fi

        msg info "Create CA file and update certificates"
        echo ${ONEAPP_MINIO_ENDPOINT_CERT} | base64 --decode >> ${local_ca_folder}/ca.crt
        update-ca-certificates
    fi

    return 0
}

service_bootstrap()
{
    export DEBIAN_FRONTEND=noninteractive

    update_at_bootstrap

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

# Then for modularity purposes you can define your own functions as long as their name
# doesn't clash with the previous functions


install_deps()
{
    msg info "Run apt-get update"
    apt-get update

    msg info "Install required packages for Jenkins"
    if ! apt-get install -y ${!1} ; then
        msg error "Package(s) installation failed"
        exit 1
    fi

    if [ -n ${2} ]; then
        msg info "Install required pip packages for Jenkins"
        if ! pip install ${2} ; then
            msg error "pip package(s) installation failed"
            exit 1
        fi
    fi
}

install_docker()
{
    msg info "Add Docker official GPG key"
    install -m 0755 -d /etc/apt/keyrings

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc

    chmod a+r /etc/apt/keyrings/docker.asc

    msg info "Add Docker repository to apt sources"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt update

    msg info "Install Docker Engine"
    if ! apt-get install -y docker-ce=$DOCKER_VERSION docker-ce-cli=$DOCKER_VERSION containerd.io docker-buildx-plugin docker-compose-plugin ; then
        msg error "Docker installation failed"
        exit 1
    fi
}

install_whatever()
{
    msg info "Install Lithops from pip"
    if ! pip install lithops==${LITHOPS_VERSION} ; then
        msg error "Error installing Lithops"
        exit 1
    fi

    msg info "Create /etc/lithops folder"
    mkdir /etc/lithops
}

create_lithops_config()
{
    msg info "Create default config file"
    cat > /etc/lithops/config <<EOF
lithops:
  backend: localhost
  storage: localhost

# Start Compute Backend configuration
# End Compute Backend configuration

# Start Storage Backend configuration
# End Storage Backend configuration
EOF
}

configure_something(){
    :
}

update_at_bootstrap(){
    msg info "Update compute and storage backend modes"
    sed -i "s/backend: .*/backend: ${ONEAPP_LITHOPS_BACKEND}/g" /etc/lithops/config
    sed -i "s/storage: .*/storage: ${ONEAPP_LITHOPS_STORAGE}/g" /etc/lithops/config

    if [[ ${ONEAPP_LITHOPS_STORAGE} = "localhost" ]]; then
        msg info "Edit config file for localhost Storage Backend"
        sed -i -ne "/# Start Storage/ {p;" -e ":a; n; /# End Storage/ {p; b}; ba}; p" /etc/lithops/config
    elif [[ ${ONEAPP_LITHOPS_STORAGE} = "minio" ]]; then
        msg info "Edit config file for MinIO Storage Backend"
        if ! check_minio_attrs; then
            echo
            msg error "MinIO configuration failed"
            msg info "You have to provide endpoint, access key id and secrec access key to configure MinIO storage backend"
            exit 1
        else
            msg info "Adding MinIO configuration to /etc/lithops/config"
            sed -i -ne "/# Start Storage/ {p; iminio:\n  endpoint: ${ONEAPP_MINIO_ENDPOINT}\n  access_key_id: ${ONEAPP_MINIO_ACCESS_KEY_ID}\n  secret_access_key: ${ONEAPP_MINIO_SECRET_ACCESS_KEY}\n  storage_bucket: ${ONEAPP_MINIO_BUCKET}" -e ":a; n; /# End Storage/ {p; b}; ba}; p" /etc/lithops/config
        fi
    fi
}

check_minio_attrs()
{
    [[ -z "$ONEAPP_MINIO_ENDPOINT" ]] && return 1
    [[ -z "$ONEAPP_MINIO_ACCESS_KEY_ID" ]] && return 1
    [[ -z "$ONEAPP_MINIO_SECRET_ACCESS_KEY" ]] && return 1

    return 0
}

postinstall_cleanup()
{
    msg info "Delete cache and stored packages"
    apt-get autoclean
    apt-get autoremove
    rm -rf /var/lib/apt/lists/*
}


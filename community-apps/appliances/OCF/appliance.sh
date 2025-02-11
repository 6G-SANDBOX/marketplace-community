#!/usr/bin/env bash

# This script contains an example implementation logic for your appliances.
# For this example the goal will be to have a "database as a service" appliance

set -o errexit -o pipefail

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
OCF_VERSION="v2.0.0-release"



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

    # docker
    install_docker

    # nginx
    # install_nginx

    # service metadata. Function defined at one-apps/appliances/lib/common.sh
    # create_one_service_metadata

    # create local folders to run capif services.
    create_local_folders

    # Download locally the docker images
    download_images

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

    run_docker_compose

    return 0
}

service_bootstrap()
{
    export DEBIAN_FRONTEND=noninteractive

    update_at_bootstrap

    msg info "Starting OpenCAPIF Services"
    run_docker_compose


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

create_local_folders()
{
    msg info "Create Local Folders for each service"
    services=(
        "TS29222_CAPIF_API_Invoker_Management_API"
        "TS29222_CAPIF_API_Provider_Management_API"
        "TS29222_CAPIF_Access_Control_Policy_API"
        "TS29222_CAPIF_Auditing_API"
        "TS29222_CAPIF_Discover_Service_API"
        "TS29222_CAPIF_Events_API"
        "TS29222_CAPIF_Logging_API_Invocation_API"
        "TS29222_CAPIF_Publish_Service_API"
        "TS29222_CAPIF_Routing_Info_API"
        "TS29222_CAPIF_Security_API"
        "helper"
        "mock_server"
        "monitoring"
        "nginx"
        "redis-data"
        "redis.conf"
        "register"
        "vault"
    )
    for service in "${services[@]}"; do
        msg info "Create Local Folders for $service"
        mkdir -p /etc/one-appliance/service.d/$service
    done
}

download_images()
{
    msg info "Pull all openCAPIF images from etsi repository of version ${OCF_VERSION}"
    images=(
        labs.etsi.org:5050/ocf/capif/prod/helper:${OCF_VERSION}
        labs.etsi.org:5050/ocf/capif/prod/ocf-access-control-policy-api:${OCF_VERSION}
        labs.etsi.org:5050/ocf/capif/prod/ocf-api-invoker-management-api:${OCF_VERSION}
        labs.etsi.org:5050/ocf/capif/prod/ocf-api-provider-management-api:${OCF_VERSION}
        labs.etsi.org:5050/ocf/capif/prod/ocf-auditing-api:${OCF_VERSION}
        labs.etsi.org:5050/ocf/capif/prod/ocf-discover-service-api:${OCF_VERSION}
        labs.etsi.org:5050/ocf/capif/prod/ocf-events-api:${OCF_VERSION}
        labs.etsi.org:5050/ocf/capif/prod/ocf-logging-api-invocation-api:${OCF_VERSION}
        labs.etsi.org:5050/ocf/capif/prod/ocf-publish-service-api:${OCF_VERSION}
        labs.etsi.org:5050/ocf/capif/prod/ocf-routing-info-api:${OCF_VERSION}
        labs.etsi.org:5050/ocf/capif/prod/ocf-security-api:${OCF_VERSION}
        labs.etsi.org:5050/ocf/capif/prod/nginx:${OCF_VERSION}
        labs.etsi.org:5050/ocf/capif/prod/mock-server:${OCF_VERSION}
        labs.etsi.org:5050/ocf/capif/prod/register:${OCF_VERSION}
        labs.etsi.org:5050/ocf/capif/prod/vault:${OCF_VERSION}
        mongo:6.0.2
        mongo-express:1.0.0-alpha.4
        redis:alpine
    )

    for image in "${images[@]}"; do
        msg info "Pull image $service from etsi repository"
        docker pull $image
    done
}



install_nginx()
{
    apt update
    msg info "Install Nginx"
    if ! apt-get install -y nginx ; then
        msg error "Nginx installation failed"
        exit 1
    fi
    mkdir -p /etc/nginx/certs
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/nginx/certs/server.key -out /etc/nginx/certs/server.crt \
        -subj "/CN=localhost"
    cat > /etc/nginx/sites-available/default <<EOF
events {}

http {
    map \$host \$backend {
        default "127.0.0.1:8080";  # Por defecto, redirige a 8080
        register-opencapif "127.0.0.1:8084";
        opencapif "127.0.0.1:8080";
    }

    server {
        listen 443 ssl;
        server_name register-opencapif opencapif;

        ssl_certificate /etc/nginx/certs/server.crt;
        ssl_certificate_key /etc/nginx/certs/server.key;

        location / {
            proxy_pass http://\$backend;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto https;
        }
    }
}
EOF
    sudo nginx -t
    cat /etc/nginx/sites-available/default
    sudo systemctl restart nginx
    sudo systemctl enable nginx
    sudo ufw allow 443/tcp
    sudo ufw reload
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



run_docker_compose()
{
    /etc/one-appliance/service.d/run.sh -s
}
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
# Static data that will be used by the appliance on installation part of the lifecycle
DOCKER_VERSION="5:26.1.3-1~ubuntu.22.04~jammy"
OCF_VERSION="v2.0.0-release"
OCF_ROBOT_FRAMEWORK_VERSION="1.0"
# Configurable variables only for config and bootstrap, set by default on the VM Template
# ONEAPP_OCF_USER="${ONEAPP_OCF_USER:-'client'}"
# ONEAPP_OCF_PASSWORD="${ONEAPP_OCF_PASSWORD:-'password'}"


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

    # in fact not needed now, because the service is started in the bootstrap
    run_docker_compose

    return 0
}

service_bootstrap()
{
    export DEBIAN_FRONTEND=noninteractive

    update_at_bootstrap

    msg info "Starting OpenCAPIF Services"
    run_docker_compose

    msg info "Creating OpenCAPIF user"
    create_user

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
        labs.etsi.org:5050/ocf/capif/robot-tests-image:${OCF_ROBOT_FRAMEWORK_VERSION}
    )

    for image in "${images[@]}"; do
        msg info "Pull image $image from etsi repository"
        docker pull $image
    done
}


#under development
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

postinstall_cleanup()
{
    msg info "Delete cache and stored packages"
    apt-get autoclean
    apt-get autoremove
    rm -rf /var/lib/apt/lists/*
}

download_capif_repository()
{
    msg info "Download OpenCAPIF repository"
    git clone --branch ${OCF_VERSION} --single-branch https://labs.etsi.org/rep/ocf/capif.git /etc/one-appliance/service.d/capif
}

run_docker_compose()
{
    msg info "Run OpenCAPIF"
    /etc/one-appliance/service.d/run.sh -s
}

create_user()
{
    msg info "Create OpenCAPIF user"
    /etc/one-appliance/service.d/capif/services/create_users.sh -u ${ONEAPP_OCF_USER} -p ${ONEAPP_OCF_PASSWORD} -t 1
}
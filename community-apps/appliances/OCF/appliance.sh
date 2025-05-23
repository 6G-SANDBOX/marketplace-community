#!/usr/bin/env bash

set -o errexit -o pipefail

# ------------------------------------------------------------------------------
# Contextualization and global variables
# ------------------------------------------------------------------------------

# ONEAPP_OCF_USER="${ONEAPP_OCF_USER:-'client'}"
# ONEAPP_OCF_PASSWORD="${ONEAPP_OCF_PASSWORD:-'password'}"
# ONEAPP_OCF_CAPIF_HOSTNAME="${ONEAPP_OCF_CAPIF_HOSTNAME:-'capifcore'}"
# ONEAPP_OCF_REGISTER_HOSTNAME="${ONEAPP_OCF_REGISTER_HOSTNAME:-'register'}"

DOCKER_VERSION="5:26.1.3-1~ubuntu.22.04~jammy"
OCF_VERSION="v2.0.0-release"
OCF_REPOSITORY_BRANCH="staging"
REGISTRY_BASE_URL="labs.etsi.org:5050/ocf/capif/prod"
BASE_DIR=/etc/one-appliance/service.d/capif
VARIABLES_FILE="${BASE_DIR}/services/variables.sh"
DOCKER_ROBOT_IMAGE="labs.etsi.org:5050/ocf/capif/robot-tests-image"
DOCKER_ROBOT_IMAGE_VERSION=1.0
OCF_ROBOT_FRAMEWORK_VERSION="${DOCKER_ROBOT_IMAGE_VERSION}-amd64"
DOCKER_COMPOSE_CAPIF_FILE="${BASE_DIR}/services/docker-compose-capif.yml"
INGRESS_NGINX_VERSION=1.27.4
INGRESS_NGINX_DIR="${BASE_DIR}/ingress-nginx"
DOCKER_COMPOSE_INGRESS_NGINX_FILE="${INGRESS_NGINX_DIR}/docker-compose-ingress-nginx.yml"
DOCKER_COMPOSE_INGRESS_NGINX_CONF_FILE="${INGRESS_NGINX_DIR}/nginx.conf"


# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# Mandatory Functions
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------

service_install()
{
    export DEBIAN_FRONTEND=noninteractive
    systemctl stop unattended-upgrades

    # docker
    install_docker

    # install yq
    install_yq

    # Download locally the docker images
    download_images

    # download capif repository
    download_capif_repository

    # cleanup
    postinstall_cleanup

    msg info "INSTALLATION FINISHED"

    return 0
}

service_configure()
{
    export DEBIAN_FRONTEND=noninteractive

    # Configure Ingress Nginx
    configure_ingress_nginx

    # Setup environment variables for deployment
    setup_environment

    return 0
}

service_bootstrap()
{
    export DEBIAN_FRONTEND=noninteractive

    msg info "Starting OpenCAPIF Services"
    run_open_capif

    msg info "Starting Ingress Nginx"
    run_ingress_nginx

    msg info "Waiting for services to start"
    sleep 2m
    
    msg info "Creating OpenCAPIF user"
    create_user

    msg info "BOOTSTRAP FINISHED"
    return 0
}


# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# Function Definitions
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------

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

install_yq()
{
    msg info "Install yq"
    add-apt-repository ppa:rmescandon/yq
    apt update
    apt install yq -y
}

download_images()
{
    msg info "Pull all openCAPIF images from etsi repository of version ${OCF_VERSION}"
    images=(
        ${REGISTRY_BASE_URL}/helper:${OCF_VERSION}
        ${REGISTRY_BASE_URL}/ocf-access-control-policy-api:${OCF_VERSION}
        ${REGISTRY_BASE_URL}/ocf-api-invoker-management-api:${OCF_VERSION}
        ${REGISTRY_BASE_URL}/ocf-api-provider-management-api:${OCF_VERSION}
        ${REGISTRY_BASE_URL}/ocf-auditing-api:${OCF_VERSION}
        ${REGISTRY_BASE_URL}/ocf-discover-service-api:${OCF_VERSION}
        ${REGISTRY_BASE_URL}/ocf-events-api:${OCF_VERSION}
        ${REGISTRY_BASE_URL}/ocf-logging-api-invocation-api:${OCF_VERSION}
        ${REGISTRY_BASE_URL}/ocf-publish-service-api:${OCF_VERSION}
        ${REGISTRY_BASE_URL}/ocf-routing-info-api:${OCF_VERSION}
        ${REGISTRY_BASE_URL}/ocf-security-api:${OCF_VERSION}
        ${REGISTRY_BASE_URL}/nginx:${OCF_VERSION}
        ${REGISTRY_BASE_URL}/mock-server:${OCF_VERSION}
        ${REGISTRY_BASE_URL}/register:${OCF_VERSION}
        ${REGISTRY_BASE_URL}/vault:${OCF_VERSION}
        mongo:6.0.2
        mongo-express:1.0.0-alpha.4
        redis:alpine
        ${DOCKER_ROBOT_IMAGE}:${OCF_ROBOT_FRAMEWORK_VERSION}
        nginx:${INGRESS_NGINX_VERSION}
    )

    for image in "${images[@]}"; do
        msg info "Pull image $image from etsi repository"
        docker pull $image
    done
}

download_capif_repository()
{
    msg info "Download OpenCAPIF repository"
    git clone --branch ${OCF_REPOSITORY_BRANCH} --single-branch https://labs.etsi.org/rep/ocf/capif.git ${BASE_DIR}
}

configure_ingress_nginx()
{
    msg info "Deploy Ingress Nginx"
    mkdir $INGRESS_NGINX_DIR
    # Create nginx configuration file
    cat > $DOCKER_COMPOSE_INGRESS_NGINX_CONF_FILE <<EOF
worker_processes auto;
error_log /var/log/nginx/error.log debug;  # Modo debug

events {
    worker_connections 1024;
}

stream {
    log_format basic '\$remote_addr [\$time_local] '
                     '"\$protocol" "\$ssl_preread_server_name" '
                     '=> "\$backend"';

    access_log /var/log/nginx/access.log basic;

    map \$ssl_preread_server_name \$backend {
        ${ONEAPP_OCF_REGISTER_HOSTNAME} 127.0.0.1:8084;
        ${ONEAPP_OCF_CAPIF_HOSTNAME} 127.0.0.1:8443;
        default 127.0.0.1:8080;  # En caso de que el hostname no coincida
    }

    server {
        listen 443;
        proxy_pass \$backend;
        ssl_preread on;
    }
}
EOF
    # Create nginx docker compose file
    msg info "Create docker-compose file for Ingress Nginx"
    cat > $DOCKER_COMPOSE_INGRESS_NGINX_FILE <<EOF
services:
  nginx:
    image: nginx:${INGRESS_NGINX_VERSION}
    container_name: nginx_proxy
    ports:
      - "443:443"  # port 443 of host exposed
    volumes:
      - $DOCKER_COMPOSE_INGRESS_NGINX_CONF_FILE:/etc/nginx/nginx.conf:ro  # nginx configuration
    network_mode: "host"  # use host network
    restart: unless-stopped
EOF

}

setup_environment()
{
    msg info "Setup OpenCAPIF environment"
    sed -i "s|^export REGISTRY_BASE_URL=.*|export REGISTRY_BASE_URL=\"$REGISTRY_BASE_URL\"|" "$VARIABLES_FILE"
    sed -i "s|^export OCF_VERSION=.*|export OCF_VERSION=\"$OCF_VERSION\"|" "$VARIABLES_FILE"
    sed -i "s|^export CAPIF_HOSTNAME=.*|export CAPIF_HOSTNAME=\"$ONEAPP_OCF_CAPIF_HOSTNAME\"|" "$VARIABLES_FILE"
    sed -i "s|^export CAPIF_HTTPS_PORT=.*|export CAPIF_HTTPS_PORT=\"443\"|" "$VARIABLES_FILE"
    sed -i "s|^export CAPIF_REGISTER=.*|export CAPIF_REGISTER=\"$ONEAPP_OCF_REGISTER_HOSTNAME\"|" "$VARIABLES_FILE"
    sed -i "s|^export CAPIF_REGISTER_PORT=.*|export CAPIF_REGISTER_PORT=\"443\"|" "$VARIABLES_FILE"
    sed -i "s|^export BUILD_DOCKER_IMAGES=.*|export BUILD_DOCKER_IMAGES=false|" "$VARIABLES_FILE"
    sed -i "s|^export DOCKER_ROBOT_IMAGE_VERSION=.*|export DOCKER_ROBOT_IMAGE_VERSION=$DOCKER_ROBOT_IMAGE_VERSION|" "$VARIABLES_FILE"
    sed -i "s|^export DOCKER_ROBOT_IMAGE=.*|export DOCKER_ROBOT_IMAGE=$DOCKER_ROBOT_IMAGE|" "$VARIABLES_FILE"
    sed -i "s|^export DOCKER_ROBOT_TTY_OPTIONS=.*|export DOCKER_ROBOT_TTY_OPTIONS="-i"|" "$VARIABLES_FILE"

    # Edit docker-compose-capif to expose nginx on port 8443 and leave 443 for ingress nginx
    msg info "Expose OpenCAPIF services on port 8080 and 8443"
    yq eval ".services.nginx.ports[0] = \"8080:8080\"" -i "$DOCKER_COMPOSE_CAPIF_FILE"
    yq eval ".services.nginx.ports[1] = \"8443:443\"" -i "$DOCKER_COMPOSE_CAPIF_FILE"

}

run_open_capif()
{
    msg info "Run OpenCAPIF"
    ${BASE_DIR}/services/clean_capif_docker_services.sh -a -z false
    ${BASE_DIR}/services/run.sh -s
}

run_ingress_nginx(){
    msg info "Run Ingress Nginx"
    docker compose -f ${DOCKER_COMPOSE_INGRESS_NGINX_FILE} up -d
}

create_user()
{
    msg info "Create OpenCAPIF user"
    ${BASE_DIR}/services/create_users.sh -u ${ONEAPP_OCF_USER} -p ${ONEAPP_OCF_PASSWORD} -t 1
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

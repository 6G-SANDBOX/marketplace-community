#!/usr/bin/env bash

set -o errexit -o pipefail

# ------------------------------------------------------------------------------
# Contextualization and global variables
# ------------------------------------------------------------------------------

ONEAPP_TNLCM_JENKINS_HOST="${ONEAPP_TNLCM_JENKINS_HOST:-127.0.0.1}"
ONEAPP_TNLCM_JENKINS_USERNAME="${ONEAPP_TNLCM_JENKINS_USERNAME:-admin}"
ONEAPP_TNLCM_ADMIN_USER="${ONEAPP_TNLCM_ADMIN_USER:-tnlcm}"

DEP_PKGS="build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev libffi-dev pkg-config wget apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common"
PYTHON_VERSION="3.13"
# PYTHON_BIN="python${PYTHON_VERSION}"   # unused
TNLCM_VERSION='v0.4.5'
BACKEND_PATH="/opt/TNLCM_BACKEND"
# FRONTEND_PATH="/opt/TNLCM_FRONTEND"
UV_PATH="/opt/uv"
UV_BIN="${UV_PATH}/uv"
MONGODB_VERSION="8.0"
YARN_GLOBAL_LIBRARIES="/opt/yarn_global"
MONGO_EXPRESS_VERSION="v1.1.0-rc-3"
MONGO_EXPRESS_PATH=/opt/mongo-express-${MONGO_EXPRESS_VERSION}


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

    # python
    install_python

    # mongodb
    install_mongodb

    # uv
    install_uv

    # tnlcm backend
    install_tnlcm_backend

    # nodejs
    install_nodejs

    # tnlcm frontend
    # install_tnlcm_frontend

    # yarn
    install_yarn

    # yarn dotenv
    install_dotenv

    # mongo-express
    install_mongo_express

    systemctl daemon-reload

    # cleanup
    postinstall_cleanup

    msg info "INSTALLATION FINISHED"

    return 0
}

service_configure()
{
    export DEBIAN_FRONTEND=noninteractive

    # update enviromental vars
    update_envfiles

    exec_ping_mongo

    load_tnlcm_database

    msg info "Start mongo-express service"
    systemctl enable --now mongo-express.service

    msg info "Start tnlcm backend service"
    systemctl enable --now tnlcm-backend.service
    if [ $? -ne 0 ]; then
        msg error "Error starting tnlcm-backend.service, aborting..."
        exit 1
    else
        msg info "tnlcm-backend.service was started..."
    fi

    # systemctl enable --now tnlcm-frontend.service
    # if [ $? -ne 0 ]; then
    #     msg error "Error starting tnlcm-frontend.service, aborting..."
    #     exit 1
    # else
    #     msg info "tnlcm-frontend.service was started..."
    # fi

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

    msg info "Install required packages for TNLCM"
    wait_for_dpkg_lock_release
    if ! apt-get install -y ${DEP_PKGS} ; then
        msg error "Package(s) installation failed"
        exit 1
    fi
}

install_python()
{
    msg info "Install python version ${PYTHON_VERSION}"
    add-apt-repository ppa:deadsnakes/ppa -y
    wait_for_dpkg_lock_release
    apt-get install python${PYTHON_VERSION}-full -y
}

install_mongodb()
{
    msg info "Install mongoDB"
    curl -fsSL https://www.mongodb.org/static/pgp/server-${MONGODB_VERSION}.asc | sudo gpg -o /usr/share/keyrings/mongodb-server-${MONGODB_VERSION}.gpg --dearmor
    echo "deb [ arch=amd64 signed-by=/usr/share/keyrings/mongodb-server-${MONGODB_VERSION}.gpg ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -sc 2> /dev/null)/mongodb-org/${MONGODB_VERSION} multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}.list
    wait_for_dpkg_lock_release
    apt-get update
    if ! apt-get install -y mongodb-org; then
        msg error "Error installing package 'mongo-org'"
        exit 1
    fi

    sudo systemctl daemon-reload

    msg info "Start mongoDB service"
    systemctl enable --now mongod.service
}

install_uv()
{
    msg info "Install uv"
    curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=${UV_PATH} sh
}

install_tnlcm_backend()
{
    msg info "Clone TNLCM Repository"
    git clone --depth 1 --branch ${TNLCM_VERSION} -c advice.detachedHead=false https://github.com/6G-SANDBOX/TNLCM.git ${BACKEND_PATH}
    # git clone --depth 1 --branch main -c advice.detachedHead=false https://github.com/6G-SANDBOX/TNLCM.git ${BACKEND_PATH}
    cp ${BACKEND_PATH}/.env.template ${BACKEND_PATH}/.env

    msg info "Generate .venv/ directory and install dependencies"
    ${UV_BIN} --directory ${BACKEND_PATH} sync

    msg info "Define TNLCM backend systemd service"
    cat > /etc/systemd/system/tnlcm-backend.service << EOF
[Unit]
Description=TNLCM Backend

[Service]
Type=simple
WorkingDirectory=${BACKEND_PATH}/
ExecStart=/bin/bash -c '${UV_BIN} run gunicorn -c conf/gunicorn_conf.py'
Restart=always

[Install]
WantedBy=multi-user.target
EOF
}

install_nodejs()
{
    msg info "Install Node.js and dependencies"
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    wait_for_dpkg_lock_release
    apt-get install -y nodejs
    npm install -g npm
}

install_yarn()
{
    msg info "Install yarn"
    curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
    echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
    wait_for_dpkg_lock_release
    apt-get update
    apt-get install -y yarn
}

install_tnlcm_frontend()
{
    msg info "Clone TNLCM_FRONTEND Repository"
    git clone --depth 1 https://github.com/6G-SANDBOX/TNLCM_FRONTEND.git ${FRONTEND_PATH}
    cp ${FRONTEND_PATH}/.env.template ${FRONTEND_PATH}/.env

    npm --prefix ${FRONTEND_PATH}/ install

    msg info "Define TNLCM frontend systemd service"
    cat > /etc/systemd/system/tnlcm-frontend.service << EOF
[Unit]
Description=TNLCM Frontend

[Service]
Type=simple
WorkingDirectory=${FRONTEND_PATH}/
ExecStart=/bin/bash -c '/usr/bin/npm run dev'
Restart=always

[Install]
WantedBy=multi-user.target
EOF
}

install_dotenv()
{
    msg info "Install dotenv library"
    yarn config set global-folder ${YARN_GLOBAL_LIBRARIES}
    yarn global add dotenv
}

install_mongo_express()
{
    msg info "Clone mongo-express repository"
    git clone --depth 1 --branch ${MONGO_EXPRESS_VERSION} -c advice.detachedHead=false https://github.com/mongo-express/mongo-express.git ${MONGO_EXPRESS_PATH}
    cd ${MONGO_EXPRESS_PATH}
    yarn install
    yarn build
    cd

    msg info "Define mongo-express systemd service"
    cat > /etc/systemd/system/mongo-express.service << EOF
[Unit]
Description=Mongo Express

[Service]
Type=simple
WorkingDirectory=${MONGO_EXPRESS_PATH}
ExecStart=/bin/bash -ac 'source ${BACKEND_PATH}/.env && yarn start'
Restart=always

[Install]
WantedBy=multi-user.target
EOF
}

update_envfiles()
{
    TNLCM_HOST=$(hostname -I | awk '{print $1}')
    declare -A var_map=(
        ["JENKINS_HOST"]="ONEAPP_TNLCM_JENKINS_HOST"
        ["JENKINS_USERNAME"]="ONEAPP_TNLCM_JENKINS_USERNAME"
        ["JENKINS_PASSWORD"]="ONEAPP_TNLCM_JENKINS_PASSWORD"
        ["JENKINS_TOKEN"]="ONEAPP_TNLCM_JENKINS_TOKEN"
        ["SITES_TOKEN"]="ONEAPP_TNLCM_SITES_TOKEN"
        ["TNLCM_HOST"]="TNLCM_HOST"
        ["TNLCM_ADMIN_USER"]="ONEAPP_TNLCM_ADMIN_USER"
        ["TNLCM_ADMIN_PASSWORD"]="ONEAPP_TNLCM_ADMIN_PASSWORD"
    )

    msg info "Update enviromental variables with the input parameters"
    for env_var in "${!var_map[@]}"; do

        if [ -z "${!var_map[$env_var]}" ]; then
            msg warning "Variable ${var_map[$env_var]} is not defined or empty"
        else
            sed -i "s%^${env_var}=.*%${env_var}=\"${!var_map[$env_var]}\"%" ${BACKEND_PATH}/.env
            msg debug "Variable ${env_var} overwritten with value ${!var_map[$env_var]}"
        fi

    done

    # msg info "Update enviromental variables of the TNLCM frontend"
    # sed -i "s%^NEXT_PUBLIC_LINKED_TNLCM_BACKEND_HOST=.*%NEXT_PUBLIC_LINKED_TNLCM_BACKEND_HOST=\"${TNLCM_HOST}\"%" ${FRONTEND_PATH}/.env
    # msg debug "Variable NEXT_PUBLIC_LINKED_TNLCM_BACKEND_HOST overwritten with value ${TNLCM_HOST}"
}

exec_ping_mongo() {
    msg info "Waiting for MongoDB to be ready..."
    while ! mongosh --eval "db.adminCommand('ping')" > /dev/null 2>&1; do
        msg info "MongoDB is not ready yet. Retrying in 10 seconds..."
        sleep 10s
    done
    msg info "MongoDB is ready"
}

load_tnlcm_database()
{
    msg info "Load TNLCM database"
    if ! mongosh --file "${BACKEND_PATH}/core/database/tnlcm-structure.js"; then
        msg error "Error creating the TNLCM database"
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
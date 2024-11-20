#!/usr/bin/env bash

set -o errexit -o pipefail

# ------------------------------------------------------------------------------
# Appliance metadata
# ------------------------------------------------------------------------------

ONE_SERVICE_NAME='6G-Sandbox TNLCM'
ONE_SERVICE_VERSION='v0.4.3'   #latest
ONE_SERVICE_BUILD=$(date +%s)
ONE_SERVICE_SHORT_DESCRIPTION='6G-Sandbox TNLCM appliance for KVM'
ONE_SERVICE_DESCRIPTION=$(cat <<EOF
This appliance installs the latest version of [TNLCM](https://github.com/6G-SANDBOX/TNLCM) and [TNLCM_FRONTEND](https://github.com/6G-SANDBOX/TNLCM_FRONTEND) from the official repositories and configures them according to the input variables. Configuration of the TNLCM can be made when instanciating the VM.

The image is based on an Ubuntu 24.04 cloud image with the OpenNebula [contextualization package](http://docs.opennebula.io/6.6/management_and_operations/references/kvm_contextualization.html).

After deploying the appliance, check the status of the deployment in /etc/one-appliance/status. You chan check the appliance logs in /var/log/one-appliance/.

**Note**: The TNLCM backend uses a MONGO database, so the VM needs to be virtualized with a CPU model that supports AVX instructions. The default CPU model in the template is host_passthrough, but if you are interested in VM live migration,
change it to a CPU model similar to your host's CPU that supports [x86-64v2 or higher](https://www.qemu.org/docs/master/system/i386/cpu.html).
EOF
)

ONE_SERVICE_RECONFIGURABLE=true


# ------------------------------------------------------------------------------
# List of contextualization parameters
# ------------------------------------------------------------------------------

ONE_SERVICE_PARAMS=(
    'ONEAPP_TNLCM_JENKINS_HOST'            'configure'  'IP address of the Jenkins server used to deploy the Trial Networks'                                       'M|text'
    'ONEAPP_TNLCM_JENKINS_USERNAME'        'configure'  'Username used to login into the Jenkins server to access and retrieve pipeline info'                      'M|text'
    'ONEAPP_TNLCM_JENKINS_PASSWORD'        'configure'  'Password used to login into the Jenkins server to access and retrieve pipeline info'                      'M|password'
    'ONEAPP_TNLCM_JENKINS_TOKEN'           'configure'  'Token to authenticate while sending POST requests to the Jenkins Server API'                              'M|password'
    'ONEAPP_TNLCM_SITES_TOKEN'             'configure'  'Token to encrypt and decrypt the 6G-Sandbox-Sites repository files for your site using Ansible Vault'     'M|password'
    'ONEAPP_TNLCM_ADMIN_USER'              'configure'  'Name of the TNLCM admin user. Default: tnlcm'                                                             'O|text'
    'ONEAPP_TNLCM_ADMIN_PASSWORD'          'configure'  'Password of the TNLCM admin user. Default: tnlcm'                                                         'O|password'
)

ONEAPP_TNLCM_JENKINS_HOST="${ONEAPP_TNLCM_JENKINS_HOST:-127.0.0.1}"
ONEAPP_TNLCM_JENKINS_USERNAME="${ONEAPP_TNLCM_JENKINS_USERNAME:-admin}"
ONEAPP_TNLCM_JENKINS_PASSWORD="${ONEAPP_TNLCM_JENKINS_PASSWORD:-admin}"
ONEAPP_TNLCM_MAIL_USERNAME="${ONEAPP_TNLCM_MAIL_USERNAME:-tnlcm.uma@gmail.com}"
ONEAPP_TNLCM_MAIL_PASSWORD="${ONEAPP_TNLCM_MAIL_PASSWORD:-czrs rsdg ktpm rrlx}"
ONEAPP_TNLCM_ADMIN_USER="${ONEAPP_TNLCM_ADMIN_USER:-tnlcm}"
ONEAPP_TNLCM_ADMIN_PASSWORD="${ONEAPP_TNLCM_ADMIN_PASSWORD:-tnlcm}"


# ------------------------------------------------------------------------------
# Global variables
# ------------------------------------------------------------------------------

DEP_PKGS="build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev libffi-dev pkg-config wget apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common"

PYTHON_VERSION="3.13"
PYTHON_BIN="python${PYTHON_VERSION}"

POETRY_FOLDER="/opt/poetry"
POETRY_BIN="/opt/poetry/bin/poetry"
BACKEND_PATH="/opt/TNLCM_BACKEND"
# FRONTEND_PATH="/opt/TNLCM_FRONTEND"
MONGODB_VERSION="8.0"
YARN_GLOBAL_LIBRARIES="/opt/yarn_global"
MONGO_EXPRESS_VERSION="v1.0.2"
MONGO_EXPRESS_PATH=/opt/mongo-express-${MONGO_EXPRESS_VERSION}


# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# Mandatory Functions
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------

service_install()
{
    export DEBIAN_FRONTEND=noninteractive
    systemctl stop unattended-upgrades

    # packages
    install_pkg_deps DEP_PKGS

    # python
    install_python

    # mongodb
    install_mongodb

    # poetry
    install_poetry

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

    # service metadata
    create_one_service_metadata

    # cleanup
    postinstall_cleanup

    # update enviromental vars
    update_envfiles

    load_tnlcm_database

    msg info "Start mongo-express service"
    systemctl enable --now mongo-express.service

    while ! systemctl is-active --quiet mongo-express.service; do
        msg debug "mongo-express service is not active yet, waiting..."
        sleep 2s
    done

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

    msg info "INSTALLATION FINISHED"

    return 0
}

# Si ONE_SERVICE_RECONFIGURABLE=false solo se ejecuta cuando se arranca por primera vez la VM
# Si ONE_SERVICE_RECONFIGURABLE=true se ejecuta cada vez que se arranca la VM por poweroff o undeploy
service_configure()
{
    export DEBIAN_FRONTEND=noninteractive

    msg info "CONFIGURATION FINISHED"
    return 0
}

# Se ejecuta cada vez que se arranca la VM por poweroff o undeploy
service_bootstrap()
{
    export DEBIAN_FRONTEND=noninteractive

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

    msg info "Install required packages for TNLCM"
    if ! apt-get install -y ${!1} ; then
        msg error "Package(s) installation failed"
        exit 1
    fi
}

install_python()
{
    msg info "Install python version ${PYTHON_VERSION}"
    add-apt-repository ppa:deadsnakes/ppa -y
    apt-get install python${PYTHON_VERSION}-full -y
}

install_mongodb()
{
    msg info "Install mongoDB"
    curl -fsSL https://www.mongodb.org/static/pgp/server-${MONGODB_VERSION}.asc | sudo gpg -o /usr/share/keyrings/mongodb-server-${MONGODB_VERSION}.gpg --dearmor
    echo "deb [ arch=amd64 signed-by=/usr/share/keyrings/mongodb-server-${MONGODB_VERSION}.gpg ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -sc 2> /dev/null)/mongodb-org/${MONGODB_VERSION} multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}.list
    apt-get update
    if ! apt-get install -y mongodb-org; then
        msg error "Error installing package 'mongo-org'"
        exit 1
    fi

    msg info "Start mongoDB service"
    systemctl enable --now mongod

    msg info "Wait for MongoDB service to be active"
    while ! systemctl is-active --quiet mongod; do
        msg debug "MongoDB service is not active yet, waiting..."
        sleep 2s
    done
}

install_poetry()
{
    msg info "Install poetry"
    curl -sSL https://install.python-poetry.org | POETRY_HOME=${POETRY_FOLDER} python3 -
    msg info "Config poetry"
    ${POETRY_BIN} config virtualenvs.in-project true
}

install_tnlcm_backend()
{
    msg info "Clone TNLCM Repository"
    git clone --depth 1 --branch ${ONE_SERVICE_VERSION} -c advice.detachedHead=false https://github.com/6G-SANDBOX/TNLCM.git ${BACKEND_PATH}
    # git clone --depth 1 --branch develop -c advice.detachedHead=false https://github.com/6G-SANDBOX/TNLCM.git ${BACKEND_PATH}
    cp ${BACKEND_PATH}/.env.template ${BACKEND_PATH}/.env

    msg info "Generate .venv/ directory and install dependencies"
    ${POETRY_BIN} install --no-root --directory ${BACKEND_PATH}

    msg info "Define TNLCM backend systemd service"
    cat > /etc/systemd/system/tnlcm-backend.service << EOF
[Unit]
Description=TNLCM Backend

[Service]
Type=simple
WorkingDirectory=${BACKEND_PATH}/
ExecStart=/bin/bash -c '${POETRY_BIN} run gunicorn -c conf/gunicorn_conf.py'
Restart=always

[Install]
WantedBy=multi-user.target
EOF
}

install_nodejs()
{
    msg info "Install Node.js and dependencies"
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    apt-get install -y nodejs
    npm install -g npm
}

install_yarn()
{
    msg info "Install yarn"
    curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
    echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
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
    git clone --depth 1 --branch release/${MONGO_EXPRESS_VERSION} -c advice.detachedHead=false https://github.com/mongo-express/mongo-express.git ${MONGO_EXPRESS_PATH}
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
    TNLCM_HOST=$(ip addr show eth0 | grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' | head -n 1)
    declare -A var_map=(
        ["JENKINS_HOST"]="ONEAPP_TNLCM_JENKINS_HOST"
        ["JENKINS_USERNAME"]="ONEAPP_TNLCM_JENKINS_USERNAME"
        ["JENKINS_PASSWORD"]="ONEAPP_TNLCM_JENKINS_PASSWORD"
        ["JENKINS_TOKEN"]="ONEAPP_TNLCM_JENKINS_TOKEN"
        ["SITES_TOKEN"]="ONEAPP_TNLCM_SITES_TOKEN"
        ["MAIL_USERNAME"]="ONEAPP_TNLCM_MAIL_USERNAME"
        ["MAIL_PASSWORD"]="ONEAPP_TNLCM_MAIL_PASSWORD"
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

load_tnlcm_database()
{
    msg info "Load TNLCM database"
    msg info "Extract mongo database name from .env file"
    # tnlcm_database=$(grep -oP 'MONGO_DATABASE=.*' ${BACKEND_PATH}/.env | cut -d'=' -f2)
    # msg info "Check TNLCM database is created"
    # db_exists=$(mongosh --quiet --eval "db.adminCommand('listDatabases').databases.map(db => db.name).includes(${tnlcm_database})")
    # msg info "If database does not exist, create it"
    # if [[ "${db_exists}" == "false" ]]; then
    msg info "Database ${tnlcm_database} not found, creating..."
    if ! mongosh --file "${BACKEND_PATH}/core/database/tnlcm-structure.js"; then
        msg error "Error creating the TNLCM database"
        exit 1
    fi
    # else
    #     msg info "Database ${tnlcm_database} already exists"
    # fi
}

postinstall_cleanup()
{
    msg info "Delete cache and stored packages"
    apt-get autoclean
    apt-get autoremove
    rm -rf /var/lib/apt/lists/*
}
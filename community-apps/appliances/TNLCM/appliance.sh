#!/usr/bin/env bash

set -o errexit -o pipefail

# ------------------------------------------------------------------------------
# Appliance metadata
# ------------------------------------------------------------------------------

ONE_SERVICE_NAME='6G-Sandbox TNLCM'
ONE_SERVICE_VERSION='v0.3.2'   #latest
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
    'ONEAPP_TNLCM_JENKINS_PASSWORD'        'configure'  'Password used to login into the Jenkins server to access and retrieve pipeline info'                      'M|text'
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
# PYTHON_BIN="/usr/local/bin/python${PYTHON_VERSION%.*}"
TNLCM_FOLDER="/opt/TNLCM"
MONGODB_VERSION="7.0"
MONGO_EXPRESS_VERSION="v1.0.2"
MONGO_EXPRESS_FOLDER=/opt/mongo-express-${MONGO_EXPRESS_VERSION}


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

    # tnlcm backend
    install_tnlcm_backend

    # tnlcm frontend
    install_tnlcm_frontend

    # mongo
    install_mongo

    # yarn
    install_yarn

    # mongo-express
    install_mongo_express

    systemctl daemon-reload

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
    export DEBIAN_FRONTEND=noninteractive

    # update enviromental vars
    update_envfiles

    msg info "CONFIGURATION FINISHED"
    return 0
}

service_bootstrap()
{
    export DEBIAN_FRONTEND=noninteractive

    systemctl enable --now mongo-express.service
    if [ $? -ne 0 ]; then
        msg error "Error starting mongo-express.service, aborting..."
        exit 1
    else
        msg info "mongo-express.service was started..."
    fi

    systemctl enable --now tnlcm-backend.service
    if [ $? -ne 0 ]; then
        msg error "Error starting tnlcm-backend.service, aborting..."
        exit 1
    else
        msg info "tnlcm-backend.service was started..."
    fi

    systemctl enable --now tnlcm-frontend.service
    if [ $? -ne 0 ]; then
        msg error "Error starting tnlcm-frontend.service, aborting..."
        exit 1
    else
        msg info "tnlcm-frontend.service was started..."
    fi

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
    # wget "https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz"
    # tar xvf Python-${PYTHON_VERSION}.tgz
    # cd Python-${PYTHON_VERSION}/
    # ./configure --enable-optimizations
    # make altinstall
    # ${PYTHON_BIN} -m ensurepip --default-pip
    # ${PYTHON_BIN} -m pip install --upgrade pip setuptools wheel
    # cd
    # rm -rf Python-${PYTHON_VERSION}*
}

install_tnlcm_backend()
{
    msg info "Clone TNLCM Repository"
    git clone --depth 1 --branch release/${ONE_SERVICE_VERSION} -c advice.detachedHead=false https://github.com/6G-SANDBOX/TNLCM.git ${TNLCM_FOLDER}
    cp ${TNLCM_FOLDER}/.env.template ${TNLCM_FOLDER}/.env

    msg info "Activate TNLCM python virtual environment and install requirements"
    ${PYTHON_BIN} -m venv ${TNLCM_FOLDER}/venv
    source ${TNLCM_FOLDER}/venv/bin/activate
    ${TNLCM_FOLDER}/venv/bin/pip install -r ${TNLCM_FOLDER}/requirements.txt
    deactivate

    msg info "Define TNLCM backend systemd service"
    cat > /etc/systemd/system/tnlcm-backend.service << EOF
[Unit]
Description=TNLCM Backend

[Service]
Type=simple
WorkingDirectory=${TNLCM_FOLDER}
ExecStart=/bin/bash -c 'source venv/bin/activate && ${PYTHON_BIN} app.py'
Restart=always

[Install]
WantedBy=multi-user.target
EOF
}

install_tnlcm_frontend()
{
    msg info "Clone TNLCM_FRONTEND Repository"
    git clone https://github.com/6G-SANDBOX/TNLCM_FRONTEND.git /opt/TNLCM_FRONTEND
    cp /opt/TNLCM_FRONTEND/.env.template /opt/TNLCM_FRONTEND/.env

    msg info "Install Node.js and dependencies"
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - &&\
    sudo apt-get install -y nodejs
    npm install -g npm
    npm --prefix /opt/TNLCM_FRONTEND/ install

    msg info "Define TNLCM frontend systemd service"
    cat > /etc/systemd/system/tnlcm-frontend.service << EOF
[Unit]
Description=TNLCM Frontend

[Service]
Type=simple
WorkingDirectory=/opt/TNLCM_FRONTEND
ExecStart=/bin/bash -c '/usr/bin/npm run dev'
Restart=always

[Install]
WantedBy=multi-user.target
EOF
}

install_mongo()
{
    msg info "Install mongo"
    sudo apt-get install gnupg curl
    curl -fsSL https://pgp.mongodb.com/server-${MONGODB_VERSION}.asc |  sudo gpg -o /usr/share/keyrings/mongodb-server-${MONGODB_VERSION}.gpg --dearmor
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-${MONGODB_VERSION}.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/${MONGODB_VERSION} multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}.list
    sudo apt-get update
    sudo apt-get install -y mongodb-org

    # TODO: check
    msg info "Add variables in Ubuntu environment"
    {
        echo "# MONGO-EXPRESS"
        grep -E '^\s*(TNLCM_ADMIN_USER|TNLCM_ADMIN_PASSWORD|TNLCM_ADMIN_EMAIL|MONGO_HOST|MONGO_PORT|MONGO_DATABASE|ME_CONFIG_MONGODB_ADMINUSERNAME|ME_CONFIG_MONGODB_ADMINPASSWORD|ME_CONFIG_MONGODB_ENABLE_ADMIN|ME_CONFIG_MONGODB_URL|ME_CONFIG_BASICAUTH|ME_CONFIG_SITE_SESSIONSECRET|VCAP_APP_HOST|ME_CONFIG_BASICAUTH_USERNAME|ME_CONFIG_BASICAUTH_PASSWORD)\s*=' ${TNLCM_FOLDER} | sed 's/^/export /'
    } >> ~/.bashrc

    msg info "Start mongo service"
    sudo systemctl enable --now mongod

    msg info "Load TNLCM database"
    mongosh --file ${TNLCM_FOLDER}/core/database/tnlcm-structure.js
}

install_yarn()
{
    msg info "Install yarn"
    curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
    echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
    sudo apt update
    sudo apt install yarn
}

install_mongo_express()
{
    msg info "Clone mongo-express repository"
    git clone --depth 1 --branch release/${MONGO_EXPRESS_VERSION} -c advice.detachedHead=false https://github.com/mongo-express/mongo-express.git ${MONGO_EXPRESS_FOLDER}
    cd /opt/mongo-express-${MONGO_EXPRESS_VERSION}
    yarn install
    yarn run build
    cd 

    msg info "Define mongo-express systemd service"
    cat > /etc/systemd/system/mongo-express.service << EOF
[Unit]
Description=Mongo Express

[Service]
Type=simple
WorkingDirectory=${MONGO_EXPRESS_FOLDER}
ExecStart=/bin/bash -c 'yarn start'
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
            sed -i "s%^${env_var}=.*%${env_var}=\"${!var_map[$env_var]}\"%" ${TNLCM_FOLDER}/.env
            msg debug "Variable ${env_var} overwritten with value ${!var_map[$env_var]}"
        fi

    done

    msg info "Update enviromental variables of the TNLCM frontend"
    sed -i "s%^NEXT_PUBLIC_LINKED_TNLCM_BACKEND_HOST=.*%NEXT_PUBLIC_LINKED_TNLCM_BACKEND_HOST=\"${TNLCM_HOST}\"%" /opt/TNLCM_FRONTEND/.env
    msg debug "Variable NEXT_PUBLIC_LINKED_TNLCM_BACKEND_HOST overwritten with value ${TNLCM_HOST}"
}

postinstall_cleanup()
{
    msg info "Delete cache and stored packages"
    apt-get autoclean
    apt-get autoremove
    rm -rf /var/lib/apt/lists/*
}

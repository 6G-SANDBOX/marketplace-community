#!/usr/bin/env bash

set -o errexit -o pipefail

# ------------------------------------------------------------------------------
# Appliance metadata
# ------------------------------------------------------------------------------

ONE_SERVICE_NAME='6G-Sandbox TNLCM backend+frontend'
ONE_SERVICE_VERSION='0.2.1'   #latest
ONE_SERVICE_BUILD=$(date +%s)
ONE_SERVICE_SHORT_DESCRIPTION='6G-Sandbox TNLCM backend+frontend for KVM'
ONE_SERVICE_DESCRIPTION=$(cat <<EOF
This appliance installs the latest version of [TNLCM](https://github.com/6G-SANDBOX/TNLCM) and [TNLCM_FRONTEND](https://github.com/6G-SANDBOX/TNLCM_FRONTEND) from the official repositories and configures them according to the input variables. Configuration of the TNLCM can be made when instanciating the VM.

The image is based on an Ubuntu 22.04 cloud image with the OpenNebula [contextualization package](http://docs.opennebula.io/6.6/management_and_operations/references/kvm_contextualization.html).

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
    'JENKINS_HOST'           'configure'  'IP address of the Jenkins server used to deploy the Trial Networks'                      'M|text'
    'JENKINS_USERNAME'       'configure'  'Username used to login into the Jenkins server to access and retrieve pipeline info'     'M|text'
    'JENKINS_PASSWORD'       'configure'  'Password used to login into the Jenkins server to access and retrieve pipeline info'     'M|text'
    'JENKINS_TOKEN'          'configure'  'Token to authenticate while sending POST requests to the Jenkins Server API'             'M|text'
    'ANSIBLE_VAULT'          'configure'  'Password used to decrypt the contents of the 6G-Sandbox-Sites repository file'           'M|text'
)

JENKINS_HOST="${JENKINS_HOST:-127.0.0.1}"
JENKINS_USERNAME="${JENKINS_USERNAME:-admin}"
JENKINS_PASSWORD="${JENKINS_PASSWORD:-admin}"


# ------------------------------------------------------------------------------
# Global variables
# ------------------------------------------------------------------------------

DEP_PKGS="build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev libffi-dev pkg-config wget apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common"

PYTHON_VERSION="3.12.4"
PYTHON_BIN="/usr/local/bin/python${PYTHON_VERSION%.*}"



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

    # docker
    install_docker

    # tnlcm backend
    install_tnlcm_backend

    # tnlcm frontend
    install_tnlcm_frontend

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

    # raise docker compose
    docker compose -f /opt/TNLCM/docker-compose.yml up -d

    systemctl enable --now tnlcm-backend.service
    if [ $? -ne 0 ]; then
        msg error "Error starting tnlcm-backend.service, aborting..."
        exit 1
    else
        msg info "tnlcm-backend.service was strarted..."
    fi

    systemctl enable --now tnlcm-frontend.service
    if [ $? -ne 0 ]; then
        msg error "Error starting tnlcm-frontend.service, aborting..."
        exit 1
    else
        msg info "tnlcm-frontend.service was strarted..."
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
    wget "https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz"
    tar xvf Python-${PYTHON_VERSION}.tgz
    cd Python-${PYTHON_VERSION}/
    ./configure --enable-optimizations
    make altinstall
    ${PYTHON_BIN} -m ensurepip --default-pip
    ${PYTHON_BIN} -m pip install --upgrade pip setuptools wheel
    cd
    rm -rf Python-${PYTHON_VERSION}*
}

install_docker()
{
    msg info "Add Docker official GPG key"
    install -m 0755 -d /etc/apt/keyrings

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    #curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg   # así lo tenía yo, con docker.gpg en vez de .asc

    chmod a+r /etc/apt/keyrings/docker.asc

    msg info "Add Docker repository to apt sources"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update

    msg info "Install Docker Engine"
    if ! apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin ; then
        msg error "Docker installation failed"
        exit 1
    fi
}

install_tnlcm_backend()
{
    msg info "Clone TNLCM Repository"
    git clone https://github.com/6G-SANDBOX/TNLCM.git /opt/TNLCM
    cp /opt/TNLCM/.env.template /opt/TNLCM/.env

    msg info "Activate TNLCM python virtual environment and install requirements"
    ${PYTHON_BIN} -m venv /opt/TNLCM/venv
    source /opt/TNLCM/venv/bin/activate
    ${PYTHON_BIN} -m pip install -r /opt/TNLCM/requirements.txt
    deactivate

    msg info "Define TNLCM backend systemd service"
    cat > /etc/systemd/system/tnlcm-backend.service << EOF
[Unit]
Description=TNLCM Backend

[Service]
Type=simple
WorkingDirectory=/opt/TNLCM
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

update_envfiles()
{
    TNLCM_HOST=$(ip addr show eth0 | grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' | head -n 1)

    msg info "Update enviromental variables with the input parameters"
    for var in JENKINS_HOST JENKINS_USERNAME JENKINS_PASSWORD JENKINS_TOKEN ANSIBLE_VAULT MAIL_USERNAME MAIL_PASSWORD TNLCM_HOST
    do
        if [ -z "${!var}" ]; then
            msg warning "Variable ${var} is not defined or empty"
        else
            sed -i "s%^${var}=.*%${var}=\"${!var}\"%" /opt/TNLCM/.env
            msg debug "Variable ${var} overwritten with value ${!var}"
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

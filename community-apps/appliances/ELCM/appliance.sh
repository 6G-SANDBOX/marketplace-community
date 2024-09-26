#!/usr/bin/env bash

set -o errexit -o pipefail

# ------------------------------------------------------------------------------
# Appliance metadata
# ------------------------------------------------------------------------------

ONE_SERVICE_NAME='6G-Sandbox ELCM backend+frontend'
ONE_SERVICE_VERSION='3.6.3'   #latest
ONE_SERVICE_BUILD=$(date +%s)
ONE_SERVICE_SHORT_DESCRIPTION='6G-Sandbox ELCM backend+frontend for KVM'
ONE_SERVICE_DESCRIPTION=$(cat <<EOF
This appliance installs the latest version of [ELCM](https://github.com/6G-SANDBOX/ELCM) and [ELCM_FRONTEND](https://github.com/6G-SANDBOX/portal) from the official repositories and configures them according to the input variables. Configuration of the ELCM can be made when instanciating the VM.

The image is based on an Ubuntu 22.04 cloud image with the OpenNebula [contextualization package](http://docs.opennebula.io/6.6/management_and_operations/references/kvm_contextualization.html).

After deploying the appliance, check the status of the deployment in /etc/one-appliance/status. You chan check the appliance logs in /var/log/one-appliance/.

EOF
)

ONE_SERVICE_RECONFIGURABLE=true


# ------------------------------------------------------------------------------
# List of contextualization parameters
# ------------------------------------------------------------------------------

ONE_SERVICE_PARAMS=(
    'ONEAPP_ELCM_INFLUXDB_USER'            'configure'  'Username used to login into the InfluxDB'       'M|text'
    'ONEAPP_ELCM_INFLUXDB_PASSWORD'        'configure'  'Password used to login into the InfluxDB'       'M|password'
    'ONEAPP_ELCM_INFLUXDB_DATABASE'        'configure'  'Database name'                                  'M|text'
    'ONEAPP_ELCM_GRAFANA_PASSWORD'         'configure'  'Password used to login into the Grafana'        'M|password'
)

ONEAPP_ELCM_INFLUXDB_USER="${ONEAPP_ELCM_INFLUXDB_USER:-admin}"
ONEAPP_ELCM_INFLUXDB_PASSWORD="${ONEAPP_ELCM_INFLUXDB_PASSWORD:-admin}"
ONEAPP_ELCM_INFLUXDB_HOST="127.0.0.1"
ONEAPP_ELCM_INFLUXDB_PORT="8086"
ONEAPP_ELCM_INFLUXDB_DATABASE="${ONEAPP_ELCM_INFLUXDB_DATABASE:-elcmdb}"
ONEAPP_ELCM_GRAFANA_USER="admin"
ONEAPP_ELCM_GRAFANA_PASSWORD="${ONEAPP_ELCM_GRAFANA_PASSWORD:-admin}"
ONEAPP_ELCM_GRAFANA_HOST="127.0.0.1"
ONEAPP_ELCM_GRAFANA_PORT="3000"


# ------------------------------------------------------------------------------
# Global variables
# ------------------------------------------------------------------------------

DEP_PKGS="build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev libffi-dev pkg-config wget apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common"

PYTHON_BACKEND_ELCM_VERSION="3.10.12"
PYTHON_FRONTEND_ELCM_VERSION="3.7.9"
INFLUXDB_VERSION="1.7.6"
GRAFANA_VERSION="5.4.5"
PYTHON_BACKEND_ELCM_BIN="/usr/local/bin/python${PYTHON_BACKEND_ELCM_VERSION%.*}"
PYTHON_FRONTEND_ELCM_BIN="/usr/local/bin/python${PYTHON_FRONTEND_ELCM_VERSION%.*}"



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

    # python elcm backend
    install_python_backend_elcm

    # python elcm frontend
    install_python_frontend_elcm

    # opentap
    install_opentap

    # influxdb
    install_influxdb

    # grafana
    install_grafana

    # elcm backend
    install_elcm_backend

    # elcm frontend
    install_elcm_frontend

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

    # configure user, password and database influxdb
    configure_influxdb

    # configure user, password and datasource grafana
    configure_grafana

    # create config file in ELCM backend
    create_elcm_backend_config_file

    # create config file in ELCM frontend
    create_elcm_frontend_config_file

    msg info "CONFIGURATION FINISHED"
    return 0
}

service_bootstrap()
{
    export DEBIAN_FRONTEND=noninteractive

    systemctl enable --now elcm-backend.service
    if [ $? -ne 0 ]; then
        msg error "Error starting elcm-backend.service, aborting..."
        exit 1
    else
        msg info "elcm-backend.service was strarted..."
    fi

    systemctl enable --now elcm-frontend.service
    if [ $? -ne 0 ]; then
        msg error "Error starting elcm-frontend.service, aborting..."
        exit 1
    else
        msg info "elcm-frontend.service was strarted..."
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

    msg info "Install required packages for ELCM"
    if ! apt-get install -y ${!1} ; then
        msg error "Package(s) installation failed"
        exit 1
    fi
}

install_python_backend_elcm()
{
    msg info "Install python version ${PYTHON_BACKEND_ELCM_VERSION}"
    wget "https://www.python.org/ftp/python/${PYTHON_BACKEND_ELCM_VERSION}/Python-${PYTHON_BACKEND_ELCM_VERSION}.tgz"
    tar xvf Python-${PYTHON_BACKEND_ELCM_VERSION}.tgz
    cd Python-${PYTHON_BACKEND_ELCM_VERSION}/
    ./configure --enable-optimizations
    make altinstall
    ${PYTHON_BACKEND_ELCM_BIN} -m ensurepip --default-pip
    ${PYTHON_BACKEND_ELCM_BIN} -m pip install --upgrade pip setuptools wheel
    cd
    rm -rf Python-${PYTHON_BACKEND_ELCM_VERSION}*
}

install_python_frontend_elcm()
{
    msg info "Install python version ${PYTHON_FRONTEND_ELCM_VERSION}"
    wget "https://www.python.org/ftp/python/${PYTHON_FRONTEND_ELCM_VERSION}/Python-${PYTHON_FRONTEND_ELCM_VERSION}.tgz"
    tar xvf Python-${PYTHON_FRONTEND_ELCM_VERSION}.tgz
    cd Python-${PYTHON_FRONTEND_ELCM_VERSION}/
    ./configure --enable-optimizations
    make altinstall
    ${PYTHON_FRONTEND_ELCM_BIN} -m ensurepip --default-pip
    ${PYTHON_FRONTEND_ELCM_BIN} -m pip install --upgrade pip setuptools wheel
    cd
    rm -rf Python-${PYTHON_FRONTEND_ELCM_VERSION}*
}

install_opentap()
{
    msg info "Install OpenTAP"
    curl -Lo opentap.linux https://packages.opentap.io/4.0/Objects/www/OpenTAP?os=Linux
    chmod +x ./opentap.linux
    ./opentap.linux --quiet
    rm opentap.linux
}

install_influxdb()
{
    msg info "Install InfluxDB version ${INFLUXDB_VERSION}"
    wget https://dl.influxdata.com/influxdb/releases/influxdb_${INFLUXDB_VERSION}_amd64.deb
    dpkg -i influxdb_${INFLUXDB_VERSION}_amd64.deb
    systemctl --now enable influxdb
    rm -rf influxdb_${INFLUXDB_VERSION}*
}

install_grafana()
{
    msg info "Install Grafana version ${GRAFANA_VERSION}"
    apt-get install -y adduser libfontconfig1 musl
    wget https://dl.grafana.com/oss/release/grafana_${GRAFANA_VERSION}_amd64.deb
    dpkg -i grafana_${GRAFANA_VERSION}_amd64.deb
    systemctl --now enable grafana-server
    rm -rf grafana_${GRAFANA_VERSION}*
}

install_elcm_backend()
{
    msg info "Clone ELCM BACKEND Repository"
    git clone https://github.com/6G-SANDBOX/ELCM /opt/ELCM

    msg info "Activate ELCM python virtual environment and install requirements"
    ${PYTHON_BACKEND_ELCM_BIN} -m venv /opt/ELCM/venv
    source /opt/ELCM/venv/bin/activate
    ${PYTHON_BACKEND_ELCM_BIN} -m pip install -r /opt/ELCM/requirements.txt
    deactivate

    msg info "Define ELCM backend systemd service"
    cat > /etc/systemd/system/elcm-backend.service << EOF
[Unit]
Description=ELCM Backend

[Service]
Type=simple
WorkingDirectory=/opt/ELCM
ExecStart=/bin/bash -c 'source venv/bin/activate && ${PYTHON_BACKEND_ELCM_BIN} app.py'
Restart=always

[Install]
WantedBy=multi-user.target
EOF
}

install_elcm_frontend()
{
    msg info "Clone ELCM FRONTEND Repository"
    git clone https://github.com/6G-SANDBOX/portal /opt/ELCM_FRONTEND

    msg info "Activate ELCM_FRONTEND python virtual environment and install requirements"
    ${PYTHON_FRONTEND_ELCM_VERSION} -m venv /opt/ELCM_FRONTEND/venv
    source /opt/ELCM_FRONTEND/venv/bin/activate
    ${PYTHON_FRONTEND_ELCM_VERSION} -m pip install -r /opt/ELCM_FRONTEND/requirements.txt
    deactivate

    msg info "Define ELCM frontend systemd service"
    cat > /etc/systemd/system/elcm-frontend.service << EOF
[Unit]
Description=ELCM Frontend

[Service]
Type=simple
WorkingDirectory=/opt/ELCM_FRONTEND
ExecStart=/bin/bash -c 'source venv/bin/activate && ${PYTHON_FRONTEND_ELCM_VERSION} app.py'
Restart=always

[Install]
WantedBy=multi-user.target
EOF
}

configure_influxdb()
{
    # create database
    /usr/bin/influx -execute "CREATE DATABASE ${ONEAPP_ELCM_INFLUXDB_DATABASE}"
    # create user
    /usr/bin/influx -execute "CREATE USER ${ONEAPP_ELCM_INFLUXDB_USER} WITH PASSWORD '${ONEAPP_ELCM_INFLUXDB_PASSWORD}' WITH ALL PRIVILEGES"
}

configure_grafana()
{
    if [ "${ONEAPP_ELCM_GRAFANA_PASSWORD}" != "admin" ]; then
        ONEAPP_ELCM_GRAFANA_UPDATE_PASSWORD_JSON=$(cat <<EOF
    {
    "oldPassword": "admin",
    "newPassword": "${ONEAPP_ELCM_GRAFANA_PASSWORD}",
    "confirmNew": "${ONEAPP_ELCM_GRAFANA_PASSWORD}"
    }
EOF
)
    curl -X PUT -H "Content-Type: application/json;charset=UTF-8" -d "${ONEAPP_ELCM_GRAFANA_UPDATE_PASSWORD_JSON}" http://${ONEAPP_ELCM_GRAFANA_USER}:admin@${ONEAPP_ELCM_GRAFANA_HOST}:${ONEAPP_ELCM_GRAFANA_PORT}/api/user/password
    # grafana-cli admin reset-admin-password --homepath "/usr/share/grafana" ${ONEAPP_ELCM_GRAFANA_PASSWORD}
fi

    # connect grafana with influxdb
    ONEAPP_ELCM_GRAFANA_INFLUXDB_DATASOURCE_JSON=$(cat <<EOF
    {
    "name": "${ONEAPP_ELCM_INFLUXDB_DATABASE}",
    "type": "influxdb",
    "access": "proxy",
    "url": "http://${ONEAPP_ELCM_INFLUXDB_HOST}:${ONEAPP_ELCM_INFLUXDB_PORT}",
    "password": "${ONEAPP_ELCM_INFLUXDB_PASSWORD}",
    "user": "${ONEAPP_ELCM_INFLUXDB_USER}",
    "database": "${ONEAPP_ELCM_INFLUXDB_DATABASE}",
    "basicAuth": true,
    "isDefault": true
    }
EOF
)
    curl -X POST -H "Content-Type: application/json" -d "${ONEAPP_ELCM_GRAFANA_INFLUXDB_DATASOURCE_JSON}" http://${ONEAPP_ELCM_GRAFANA_USER}:admin@${ONEAPP_ELCM_GRAFANA_HOST}:${ONEAPP_ELCM_GRAFANA_PORT}/api/datasources

    # generate API Key in grafana
    ONEAPP_ELCM_GRAFANA_API_KEY=$(cat <<EOF
    {
    "name":"elcmapikey",
    "role":"Admin"
    }
EOF
)
    ONEAPP_ELCM_API_KEY=$(curl -X POST -H "Content-Type: application/json" -d "${ONEAPP_ELCM_GRAFANA_API_KEY}" http://${ONEAPP_ELCM_GRAFANA_USER}:admin@${ONEAPP_ELCM_GRAFANA_HOST}:${ONEAPP_ELCM_GRAFANA_PORT}/api/auth/keys)
    ONEAPP_ELCM_API_KEY=$(echo "${ONEAPP_ELCM_API_KEY}" | grep -o '"key":"[^"]*"' | sed 's/"key":"\([^"]*\)"/\1/')
}

create_elcm_backend_config_file()
{
    msg info "Create file config in ELCM backend"
    cat > /opt/ELCM/config.yml << EOF
TempFolder: 'Temp'
ResultsFolder: 'Results'
VerdictOnError: 'Error'
Logging:
  Folder: 'Logs'
  AppLevel: INFO
  LogLevel: DEBUG
Portal:
  Enabled: True
  Host: '127.0.0.1'
  Port: 5000
SliceManager:
  Host: '192.168.32.136'
  Port: 8000
Tap:
  Enabled: True
  OpenTap: True
  Exe: tap
  Folder: /opt/opentap
  Results: /opt/opentap/Results
  EnsureClosed: True
  EnsureAdbClosed: False
Grafana:
  Enabled: True
  Host: "${ONEAPP_ELCM_GRAFANA_HOST}"
  Port: ${ONEAPP_ELCM_GRAFANA_PORT}
  Bearer: ${ONEAPP_ELCM_API_KEY}
ReportGenerator:
InfluxDb:
  Enabled: True
  Host: "${ONEAPP_ELCM_INFLUXDB_HOST}"
  Port: ${ONEAPP_ELCM_INFLUXDB_PORT}
  User: ${ONEAPP_ELCM_INFLUXDB_USER}
  Password: ${ONEAPP_ELCM_INFLUXDB_PASSWORD}
  Database: ${ONEAPP_ELCM_INFLUXDB_DATABASE}
Metadata:
  HostIp: "127.0.0.1"
  Facility:
EastWest:
  Enabled: False
  Timeout: 120
  Remotes:
    ExampleRemote1:
      Host: host1
      Port: port1
    ExampleRemote2:
      Host: host1
      Port: port1
EOF
}

create_elcm_frontend_config_file()
{
    msg info "Create file config in ELCM frontend"
    cat > /opt/ELCM_FRONTEND/config.yml << EOF
Dispatcher:
  Host: '127.0.0.1'
  Port: 5001

TestCases:
  - TESTBEDVALIDATION
  - REMOTEPINGSSH
  - EXOPLAYERTEST
  - REMOTEPINGSSHTOCSVRETURNANDUPLOAD

Slices:
  - Slice1
  - Slice2

UEs:
  UE_S0_IN:
    OS: Android
  UE_S0_OUT:
    OS: Android

Grafana URL:
  http://${ONEAPP_ELCM_GRAFANA_HOST}:${ONEAPP_ELCM_GRAFANA_PORT}

Platform:
  UMA

Description:
  6GSANDBOX

Logging:
  Folder: 'Logs'
  AppLevel: INFO
  LogLevel: DEBUG
EOF
}

postinstall_cleanup()
{
    msg info "Delete cache and stored packages"
    apt-get autoclean
    apt-get autoremove
    rm -rf /var/lib/apt/lists/*
}

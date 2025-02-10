#!/usr/bin/env bash

set -o errexit -o pipefail

# ------------------------------------------------------------------------------
# Global variables
# ------------------------------------------------------------------------------

ONE_SERVICE_RECONFIGURABLE=true

ONEAPP_ELCM_INFLUXDB_USER="${ONEAPP_ELCM_INFLUXDB_USER:-admin}"
ONEAPP_ELCM_INFLUXDB_PASSWORD="${ONEAPP_ELCM_INFLUXDB_PASSWORD:-admin}"
ONEAPP_ELCM_INFLUXDB_HOST="127.0.0.1"
ONEAPP_ELCM_INFLUXDB_PORT="8086"
ONEAPP_ELCM_INFLUXDB_DATABASE="${ONEAPP_ELCM_INFLUXDB_DATABASE:-elcmdb}"
ONEAPP_ELCM_GRAFANA_USER="admin"
ONEAPP_ELCM_GRAFANA_PASSWORD="${ONEAPP_ELCM_GRAFANA_PASSWORD:-admin}"
ONEAPP_ELCM_GRAFANA_HOST="127.0.0.1"
ONEAPP_ELCM_GRAFANA_PORT="3000"

DEP_PKGS="build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev libffi-dev pkg-config wget apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common libgtk-3-0 libwebkit2gtk-4.0-37 libjavascriptcoregtk-4.0-18"
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

    # packages
    install_pkg_deps

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

    # cleanup
    postinstall_cleanup

    msg info "INSTALLATION FINISHED"

    return 0
}

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
    wait_for_dpkg_lock_release
    if ! apt-get install -y ${DEP_PKGS} ; then
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
    systemctl enable --now influxdb
    rm -rf influxdb_${INFLUXDB_VERSION}*
}

install_grafana()
{
    msg info "Install Grafana version ${GRAFANA_VERSION}"
    apt-get install -y adduser libfontconfig1 musl
    wget https://dl.grafana.com/oss/release/grafana_${GRAFANA_VERSION}_amd64.deb
    dpkg -i grafana_${GRAFANA_VERSION}_amd64.deb
    systemctl enable --now grafana-server
    rm -rf grafana_${GRAFANA_VERSION}*
}

install_elcm_backend()
{
    msg info "Clone ELCM BACKEND Repository"
    git clone https://github.com/6G-SANDBOX/ELCM /opt/ELCM

    msg info "Activate ELCM python virtual environment and install requirements"
    ${PYTHON_BACKEND_ELCM_BIN} -m venv /opt/ELCM/venv
    source /opt/ELCM/venv/bin/activate
    pip install -r /opt/ELCM/requirements.txt
    deactivate

    msg info "Define ELCM backend systemd service"
    cat > /etc/systemd/system/elcm-backend.service << EOF
[Unit]
Description=ELCM Backend

[Service]
Type=simple
WorkingDirectory=/opt/ELCM
Environment="SECRET_KEY=super secret"
ExecStart=/bin/bash -c 'source venv/bin/activate && flask run --host 0.0.0.0 --port 5001'
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
    ${PYTHON_FRONTEND_ELCM_BIN} -m venv /opt/ELCM_FRONTEND/venv
    source /opt/ELCM_FRONTEND/venv/bin/activate
    pip install -r /opt/ELCM_FRONTEND/requirements.txt
    deactivate

    msg info "Define ELCM frontend systemd service"
    cat > /etc/systemd/system/elcm-frontend.service << EOF
[Unit]
Description=ELCM Frontend

[Service]
Type=simple
WorkingDirectory=/opt/ELCM_FRONTEND
Environment="SECRET_KEY=super secret"
ExecStart=/bin/bash -c 'source venv/bin/activate && flask run --host 0.0.0.0 --port 5000'
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

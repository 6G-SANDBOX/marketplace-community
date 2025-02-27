#!/usr/bin/env bash

set -o errexit -o pipefail

# ------------------------------------------------------------------------------
# Global variables
# ------------------------------------------------------------------------------

ONE_SERVICE_RECONFIGURABLE=true

ONEAPP_ELCM_INFLUXDB_USER="${ONEAPP_ELCM_INFLUXDB_USER:-admin}"
# ONEAPP_ELCM_INFLUXDB_PASSWORD="${ONEAPP_ELCM_INFLUXDB_PASSWORD:-admin}"
ONEAPP_ELCM_INFLUXDB_ORG="${ONEAPP_ELCM_INFLUXDB_ORG:-elcmorg}"
ONEAPP_ELCM_INFLUXDB_HOST="127.0.0.1"
ONEAPP_ELCM_INFLUXDB_PORT="8086"
ONEAPP_ELCM_INFLUXDB_BUCKET="${ONEAPP_ELCM_INFLUXDB_BUCKET:-elcmbucket}"
ONEAPP_ELCM_GRAFANA_USER="admin"
# ONEAPP_ELCM_GRAFANA_PASSWORD="${ONEAPP_ELCM_GRAFANA_PASSWORD:-admin}"
ONEAPP_ELCM_GRAFANA_HOST="127.0.0.1"
ONEAPP_ELCM_GRAFANA_PORT="3000"

DEP_PKGS="build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev libffi-dev pkg-config wget apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common libgtk-3-0 libwebkit2gtk-4.0-37 libjavascriptcoregtk-4.0-18"
PYTHON_VERSION="3.10"
PYTHON_BIN="python${PYTHON_VERSION}"
OPENTAP_PATH="/opt/opentap"
BACKEND_VERSION="v3.7.1"
BACKEND_PATH="/opt/ELCM_BACKEND"
FRONTEND_VERSION="v3.0.1"
FRONTEND_PATH="/opt/ELCM_FRONTEND"


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
  # install_python

  # TODO: opentap
  # install_opentap

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

install_python()
{
  msg info "Install python version ${PYTHON_VERSION}"
  add-apt-repository ppa:deadsnakes/ppa -y
  wait_for_dpkg_lock_release
  apt-get install python${PYTHON_VERSION}-full -y
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
  msg info "Install InfluxDB"
  wget -q https://repos.influxdata.com/influxdata-archive_compat.key
  echo '393e8779c89ac8d958f81f942f9ad7fb82a25e133faddaf92e15b16e6ac9ce4c influxdata-archive_compat.key' | sha256sum -c && cat influxdata-archive_compat.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/influxdata-archive_compat.gpg > /dev/null
  echo 'deb [signed-by=/etc/apt/trusted.gpg.d/influxdata-archive_compat.gpg] https://repos.influxdata.com/debian stable main' | sudo tee /etc/apt/sources.list.d/influxdata.list
  apt-get update
  apt-get install -y influxdb2
  systemctl enable --now influxdb.service
}

install_grafana()
{
  msg info "Install Grafana"
  mkdir -p /etc/apt/keyrings/
  wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
  echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee -a /etc/apt/sources.list.d/grafana.list
  apt-get update
  apt-get install -y grafana
  systemctl enable --now grafana-server.service
}

install_elcm_backend()
{
  msg info "Clone ELCM BACKEND Repository"
  git clone --depth 1 --branch ${BACKEND_VERSION} -c advice.detachedHead=false https://gitlab.com/morse-uma/elcm.git ${BACKEND_PATH}

  msg info "Activate ELCM python virtual environment and install requirements"
  ${PYTHON_BIN} -m venv ${BACKEND_PATH}/venv
  source ${BACKEND_PATH}/venv/bin/activate
  pip install -r ${BACKEND_PATH}/requirements.txt
  deactivate

  msg info "Define ELCM backend systemd service"
  cat > /etc/systemd/system/elcm-backend.service << EOF
[Unit]
Description=ELCM Backend

[Service]
Type=simple
WorkingDirectory=${BACKEND_PATH}
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
  git clone --depth 1 --branch ${FRONTEND_VERSION} -c advice.detachedHead=false https://gitlab.com/morse-uma/elcm-portal.git ${FRONTEND_PATH}

  msg info "Activate ELCM_FRONTEND python virtual environment and install requirements"
  ${PYTHON_BIN} -m venv ${FRONTEND_PATH}/venv
  source ${FRONTEND_PATH}/venv/bin/activate
  pip install -r ${FRONTEND_PATH}/requirements.txt
  deactivate

  msg info "Define ELCM frontend systemd service"
  cat > /etc/systemd/system/elcm-frontend.service << EOF
[Unit]
Description=ELCM Frontend

[Service]
Type=simple
WorkingDirectory=${FRONTEND_PATH}
Environment="SECRET_KEY=super secret"
ExecStart=/bin/bash -c 'source venv/bin/activate && flask run --host 0.0.0.0 --port 5000'
Restart=always

[Install]
WantedBy=multi-user.target
EOF
}

configure_influxdb()
{
  influx setup --host http://${ONEAPP_ELCM_INFLUXDB_HOST}:${ONEAPP_ELCM_INFLUXDB_PORT} --org ${ONEAPP_ELCM_INFLUXDB_ORG} --bucket ${ONEAPP_ELCM_INFLUXDB_BUCKET} --username ${ONEAPP_ELCM_INFLUXDB_USER} --password ${ONEAPP_ELCM_INFLUXDB_PASSWORD} --force
  INFLUXDB_USER_TOKEN=$(influx auth list --host http://${ONEAPP_ELCM_INFLUXDB_HOST}:${ONEAPP_ELCM_INFLUXDB_PORT} --json | jq -r '.[0].token')
  # influx auth create --org ${ONEAPP_ELCM_INFLUXDB_ORG} --all-access --description "Admin ELCM token" --host http://${ONEAPP_ELCM_INFLUXDB_HOST}:${ONEAPP_ELCM_INFLUXDB_PORT}
}

configure_grafana()
{
  if [ "${ONEAPP_ELCM_GRAFANA_PASSWORD}" != "admin" ]; then
#     ONEAPP_ELCM_GRAFANA_UPDATE_PASSWORD_JSON=$(cat <<EOF
#   {
#   "oldPassword": "admin",
#   "newPassword": "${ONEAPP_ELCM_GRAFANA_PASSWORD}",
#   "confirmNew": "${ONEAPP_ELCM_GRAFANA_PASSWORD}"
#   }
# EOF
# )
  # curl -X PUT -H "Content-Type: application/json;charset=UTF-8" -d "${ONEAPP_ELCM_GRAFANA_UPDATE_PASSWORD_JSON}" http://${ONEAPP_ELCM_GRAFANA_USER}:admin@${ONEAPP_ELCM_GRAFANA_HOST}:${ONEAPP_ELCM_GRAFANA_PORT}/api/user/password
  grafana-cli admin reset-admin-password ${ONEAPP_ELCM_GRAFANA_PASSWORD}
fi

  # connect grafana with influxdb
  INFLUXDB_DATASOURCE_JSON=$(cat <<EOF
{
  "name": "${ONEAPP_ELCM_INFLUXDB_BUCKET}",
  "type": "influxdb",
  "access": "proxy",
  "url": "http://${ONEAPP_ELCM_INFLUXDB_HOST}:${ONEAPP_ELCM_INFLUXDB_PORT}",
  "isDefault": true,
  "jsonData": {
    "version": "Flux",
    "organization": "${ONEAPP_ELCM_INFLUXDB_ORG}",
    "defaultBucket": "${ONEAPP_ELCM_INFLUXDB_BUCKET}",
    "httpMode": "POST"
  },
  "secureJsonData": {
    "token": "${INFLUXDB_USER_TOKEN}"
  }
}
EOF
)
  curl -X POST -H "Content-Type: application/json" -d "${INFLUXDB_DATASOURCE_JSON}" http://${ONEAPP_ELCM_GRAFANA_USER}:${ONEAPP_ELCM_GRAFANA_PASSWORD}@${ONEAPP_ELCM_GRAFANA_HOST}:${ONEAPP_ELCM_GRAFANA_PORT}/api/datasources

  # generate service account in grafana
  SERVICE_ACCOUNT_PAYLOAD=$(cat <<EOF
{
  "name": "elcmsa",
  "role": "Admin",
  "isDisabled": false
}
EOF
)
  SERVICE_ACCOUNT_RESPONSE=$(curl -X POST \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -H "Authorization: Basic $(echo -n "${ONEAPP_ELCM_GRAFANA_USER}:${ONEAPP_ELCM_GRAFANA_PASSWORD}" | base64)" \
  -d "${SERVICE_ACCOUNT_PAYLOAD}" \
  "http://${ONEAPP_ELCM_GRAFANA_HOST}:${ONEAPP_ELCM_GRAFANA_PORT}/api/serviceaccounts")

  SERVICE_ACCOUNT_ID=$(echo "${SERVICE_ACCOUNT_RESPONSE}" | grep -o '"id":[0-9]*' | cut -d ':' -f2)

  # generate token to service account
  SA_TOKEN_PAYLOAD=$(cat <<EOF
{
  "name": "elcmsa-token",
  "secondsToLive": 0
}
EOF
)

  SA_TOKEN_RESPONSE=$(curl -X POST \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -H "Authorization: Basic $(echo -n "${ONEAPP_ELCM_GRAFANA_USER}:${ONEAPP_ELCM_GRAFANA_PASSWORD}" | base64)" \
  -d "${SA_TOKEN_PAYLOAD}" \
  "http://${ONEAPP_ELCM_GRAFANA_HOST}:${ONEAPP_ELCM_GRAFANA_PORT}/api/serviceaccounts/${SERVICE_ACCOUNT_ID}/tokens")

  GRAFANA_USER_TOKEN=$(echo "${SA_TOKEN_RESPONSE}" | grep -o '"key":"[^"]*"' | sed 's/"key":"\([^"]*\)"/\1/')
}

create_elcm_backend_config_file()
{
  msg info "Create file config in ELCM backend"
  cat > ${BACKEND_PATH}/config.yml << EOF
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
  Bearer: ${GRAFANA_USER_TOKEN}
  ReportGenerator:
InfluxDb:
  Enabled: True
  Host: "${ONEAPP_ELCM_INFLUXDB_HOST}"
  Port: ${ONEAPP_ELCM_INFLUXDB_PORT}
  User: ${ONEAPP_ELCM_INFLUXDB_USER}
  Password: ${ONEAPP_ELCM_INFLUXDB_PASSWORD}
  Database: ${ONEAPP_ELCM_INFLUXDB_BUCKET}
  Token: ${INFLUXDB_USER_TOKEN}
  Org: ${ONEAPP_ELCM_INFLUXDB_ORG}
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
  cat > ${FRONTEND_PATH}/config.yml << EOF
Logging:
  Folder: 'Logs'
  AppLevel: INFO
  LogLevel: DEBUG
ELCM:
  Host: '127.0.0.1'
  Port: 5001
Grafana URL: http://${ONEAPP_ELCM_GRAFANA_HOST}:${ONEAPP_ELCM_GRAFANA_PORT}
EastWest:
  Enabled: False
  Remotes: {}  # One key for each remote Portal, each key containing 'Host' and 'Port' values
Analytics:
  Enabled: False
  URL: <Internet address>/dash # External URL of the Analytics Dashboard
  Secret: # Secret key shared with the Analytics Dashboard, used in order to create secure URLs
Branding:
  Platform: 'Untitled'
  Description: 'Untitled ELCM Portal'
  DescriptionPage: 'platform.html'
  FavIcon: 'header.png'
  Header: 'header.png'
  Logo: 'logo.png'
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

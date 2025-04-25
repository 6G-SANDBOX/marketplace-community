#!/usr/bin/env bash

set -o errexit -o pipefail

# ------------------------------------------------------------------------------
# Global variables
# ------------------------------------------------------------------------------

ONE_SERVICE_RECONFIGURABLE=false

ONEAPP_MONGODB_VERSION="${ONEAPP_MONGODB_VERSION:-8.0.8}"
ONEAPP_MONGO_EXPRESS_VERSION="v1.1.0-rc-3"
ONEAPP_MONGODB_DATABASE="${ONEAPP_MONGODB_DATABASE:-dummydatabase}"
ONEAPP_MONGODB_USER="${ONEAPP_MONGODB_USER:-admin}"
ONEAPP_MONGODB_PASSWORD="${ONEAPP_MONGODB_PASSWORD:-admin}"

ME_CONFIG_BASICAUTH="true"
ME_CONFIG_MONGODB_ENABLE_ADMIN="false"
MONGO_HOST="127.0.0.1"
MONGO_PORT="27017"
ME_CONFIG_MONGODB_URL="mongodb://${ONEAPP_MONGODB_USER}:${ONEAPP_MONGODB_PASSWORD}@${MONGO_HOST}:${MONGO_PORT}/${ONEAPP_MONGODB_DATABASE}"
ME_CONFIG_SITE_SESSIONSECRET="secret"
VCAP_APP_HOST="0.0.0.0"
MONGO_EXPRESS_PATH="/opt/mongo-express"

DEP_PKGS="build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev libffi-dev pkg-config wget apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common libgtk-3-0 libwebkit2gtk-4.0-37 libjavascriptcoregtk-4.0-18"

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

  # mongodb
  install_mongodb

  # nodejs
  install_nodejs

  # yarn
  install_yarn

  # mongo-express
  install_mongo_express

  systemctl daemon-reload

  systemctl enable --now mongod.service

  # cleanup
  postinstall_cleanup

  msg info "INSTALLATION FINISHED"

  return 0
}

service_configure()
{
  export DEBIAN_FRONTEND=noninteractive

  wait_for_mongodb_service

  exec_ping_mongodb

  systemctl daemon-reload

  configure_mongo_express
  
  systemctl enable --now mongo-express.service

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

  msg info "Install required packages for ELCM"
  wait_for_dpkg_lock_release
  if ! apt-get install -y ${DEP_PKGS} ; then
    msg error "Package(s) installation failed"
    exit 1
  fi
}

install_mongodb() {
  msg info "Install MongoDB ${ONEAPP_MONGODB_VERSION}"
  curl -fsSL https://www.mongodb.org/static/pgp/server-${ONEAPP_MONGODB_VERSION}.asc | sudo gpg -o /usr/share/keyrings/mongodb-server-${ONEAPP_MONGODB_VERSION}.gpg --dearmor
  echo "deb [ arch=amd64 signed-by=/usr/share/keyrings/mongodb-server-${ONEAPP_MONGODB_VERSION}.gpg ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -sc 2> /dev/null)/mongodb-org/${ONEAPP_MONGODB_VERSION} multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-${ONEAPP_MONGODB_VERSION}.list
  wait_for_dpkg_lock_release
  apt-get update
  if ! apt-get install -y mongodb-org; then
    msg error "Error installing package 'mongo-org'"
    exit 1
  fi
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

install_mongo_express()
{
  msg info "Clone mongo-express repository"
  git clone --depth 1 --branch ${ONEAPP_MONGO_EXPRESS_VERSION} -c advice.detachedHead=false https://github.com/mongo-express/mongo-express.git ${MONGO_EXPRESS_PATH}
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
ExecStart=/bin/bash -ac 'source ${MONGO_EXPRESS_PATH}/.env && yarn start'
Restart=always

[Install]
WantedBy=multi-user.target
EOF
}

wait_for_mongodb_service()
{
  msg info "Wait for MongoDB service to be up and running"
  local timeout=600
  local interval=5

  for ((i=0; i<timeout; i+=interval)); do
    if systemctl is-active --quiet mongod.service; then
      return 0
    fi
    msg info "MongoDB service is not active yet. Retrying in ${interval} seconds..."
    sleep "${interval}"
  done

  msg error "Error: 10m timeout without mongod.service being active"
  exit 1
}

exec_ping_mongodb() 
{
  msg info "Waiting for MongoDB to be ready..."
  while ! mongosh --eval "db.adminCommand('ping')" > /dev/null 2>&1; do
    msg info "MongoDB is not ready yet. Retrying in 10 seconds..."
    sleep 10s
  done
  msg info "MongoDB is ready"
}

configure_mongo_express()
{
  msg info "Configure mongo-express"
  cat > ${MONGO_EXPRESS_PATH}/.env << EOF
ME_CONFIG_BASICAUTH=${ME_CONFIG_BASICAUTH}
ME_CONFIG_BASICAUTH_USERNAME=${ONEAPP_MONGO_EXPRESS_USER}
ME_CONFIG_BASICAUTH_PASSWORD=${ONEAPP_MONGO_EXPRESS_PASSWORD}
ME_CONFIG_MONGODB_ENABLE_ADMIN=${ME_CONFIG_MONGODB_ENABLE_ADMIN}
ME_CONFIG_MONGODB_ADMINUSERNAME=${ONEAPP_MONGODB_USER}
ME_CONFIG_MONGODB_ADMINPASSWORD=${ONEAPP_MONGODB_PASSWORD}
ME_CONFIG_MONGODB_URL=${ME_CONFIG_MONGODB_URL}
ME_CONFIG_SITE_SESSIONSECRET=${ME_CONFIG_SITE_SESSIONSECRET}
VCAP_APP_HOST=${VCAP_APP_HOST}
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
  wait_for_dpkg_lock_release
  apt-get autoclean
  apt-get autoremove
  rm -rf /var/lib/apt/lists/*
}

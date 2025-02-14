#!/bin/bash

# Directories variables setup (no modification needed)
export SERVICES_DIR=/etc/one-appliance/service.d
# export SERVICES_DIR=/Users/jms/projects/marketplace-community/community-apps/appliances/OCF


help() {
  echo "Usage: $1 <options>"
  echo "       -c : Setup different hostname for capif"
  echo "       -s : Run Mock server"
  echo "       -m : Run monitoring service"
  echo "       -l : Set Log Level (default DEBUG). Select one of: [CRITICAL, FATAL, ERROR, WARNING, WARN, INFO, DEBUG, NOTSET]"
  echo "       -r : Remove cached information on build"
  echo "       -h : show this help"
  exit 1
}

HOSTNAME=capifcore
MONITORING_STATE=false
DEPLOY=all
LOG_LEVEL=DEBUG
CACHED_INFO=""

VERSION="v2.0.0-release"

# Needed to avoid write permissions on bind volumes with prometheus and grafana
DUID=$(id -u)
DGID=$(id -g)

# Mock Server configuration
IP=0.0.0.0
PORT=9100

# Get docker compose version
docker_version=$(docker compose version --short | cut -d',' -f1)
IFS='.' read -ra version_components <<< "$docker_version"

if [ "${version_components[0]}" -ge 2 ] && [ "${version_components[1]}" -ge 10 ]; then
  echo "Docker compose version it greater than 2.10"
else
  echo "Docker compose version is not valid. Should be greater than 2.10"
  exit 1
fi

# Read params
while getopts ":c:l:mshr" opt; do
  case $opt in
    c)
      HOSTNAME="$OPTARG"
      ;;
    m)
      MONITORING_STATE=true
      ;;
    s)
      ROBOT_MOCK_SERVER=true
      ;;
    h)
      help
      ;;
    l)
      LOG_LEVEL="$OPTARG"
      ;;
    r)
      CACHED_INFO="--no-cache"
      ;;
    \?)
      echo "Not valid option: -$OPTARG" >&2
      help
      ;;
    :)
      echo "The -$OPTARG option requires an argument." >&2
      help
      ;;
  esac
done

echo Nginx hostname will be $HOSTNAME, deploy $DEPLOY, monitoring $MONITORING_STATE

if [ "$MONITORING_STATE" == "true" ] ; then
    echo '***Monitoring set as true***'
    echo '***Creating Monitoring stack***'
    DUID=$DUID DGID=$DGID docker compose -f "$SERVICES_DIR/monitoring/docker-compose.yml" up --detach --build $CACHED_INFO

    status=$?
    if [ $status -eq 0 ]; then
        echo "*** Monitoring Stack Runing ***"
    else
        echo "*** Monitoring Stack failed to start ***"
        exit $status
    fi
fi

docker network create capif-network

OCF_VERSION=$VERSION docker compose -f "$SERVICES_DIR/docker-compose-vault.yml" up --detach --build $CACHED_INFO

status=$?
if [ $status -eq 0 ]; then
    echo "*** Vault Service Runing ***"
else
    echo "*** Vault failed to start ***"
    exit $status
fi

SERVICE_FOLDER=$SERVICES_DIR OCF_VERSION=$VERSION CAPIF_HOSTNAME=$HOSTNAME MONITORING=$MONITORING_STATE LOG_LEVEL=$LOG_LEVEL docker compose -f "$SERVICES_DIR/docker-compose-capif.yml" up --detach --build $CACHED_INFO

status=$?
if [ $status -eq 0 ]; then
    echo "*** All Capif services are running ***"
else
    echo "*** Some Capif services failed to start ***"
    exit $status
fi

CAPIF_PRIV_KEY_BASE_64=$(echo "$(cat nginx/certs/server.key)")
SERVICE_FOLDER=$SERVICES_DIR OCF_VERSION=$VERSION CAPIF_PRIV_KEY=$CAPIF_PRIV_KEY_BASE_64 LOG_LEVEL=$LOG_LEVEL docker compose -f "$SERVICES_DIR/docker-compose-register.yml" up --detach --build $CACHED_INFO

status=$?
if [ $status -eq 0 ]; then
    echo "*** Register Service are running ***"
else
    echo "*** Register Service failed to start ***"
    exit $status
fi

if [ "$ROBOT_MOCK_SERVER" == "true" ] ; then
    echo '***Robot Mock Server set as true***'
    echo '***Creating Robot Mock Server stack***'

    SERVICE_FOLDER=$SERVICES_DIR OCF_VERSION=$VERSION IP=$IP PORT=$PORT docker compose -f "$SERVICES_DIR/docker-compose-mock-server.yml" up --detach --build $CACHED_INFO
    status=$?
    if [ $status -eq 0 ]; then
        echo "*** Mock Server Running ***"
    else
        echo "*** Mock Server failed to start ***"
        exit $status
    fi
fi

exit $status

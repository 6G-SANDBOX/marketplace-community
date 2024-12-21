#!/bin/bash

# User to create
TOTAL_USERS=1
USERNAME_PREFIX=
USER_PASSWORD=

help() {
  echo "Usage: $1 <options>"
  echo "       -u : User prefix to use"
  echo "       -p : Password to set for user"
  echo "       -l : Local usage of script (default true)"
  echo "       -t : Total user to create (default 1)"  
  echo "       -h : show this help"
  exit 1
}

# Read params
while getopts ":u:p:l:t:h" opt; do
  case $opt in
    u)
      USERNAME_PREFIX="$OPTARG"
      ;;
    p)
      USER_PASSWORD=$OPTARG
      ;;
    l)
      LOCAL=$OPTARG
      ;;
    t)
      TOTAL_USERS=$OPTARG
      ;;
    h)
      help
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

if [[ "$USERNAME_PREFIX" == "" ]]
then
    echo "USERNAME_PREFIX must be set with option -u"
    help
    exit -1
fi

if [[ "$USER_PASSWORD" == "" ]]
then
    echo "USER_PASSWORD must be set with option -p"
    help
    exit -1
fi

# Other Stuff
DOCKER_ROBOT_IMAGE=labs.etsi.org:5050/ocf/capif/robot-tests-image
DOCKER_ROBOT_IMAGE_VERSION=1.0
cd ..
REPOSITORY_BASE_FOLDER=${PWD}
TEST_FOLDER=$REPOSITORY_BASE_FOLDER/tests
RESULT_FOLDER=$REPOSITORY_BASE_FOLDER/results
ROBOT_DOCKER_FILE_FOLDER=$REPOSITORY_BASE_FOLDER/tools/robot

# nginx Hostname and http port (80 by default) to reach for tests
CAPIF_REGISTER=capifcore
CAPIF_REGISTER_PORT=8084
CAPIF_HOSTNAME=capifcore
CAPIF_HTTP_PORT=8080
CAPIF_HTTPS_PORT=443

# VAULT access configuration
CAPIF_VAULT=vault
CAPIF_VAULT_PORT=8200
CAPIF_VAULT_TOKEN=read-ca-token

# Mock Server
MOCK_SERVER_URL=http://mock-server:9100
NOTIFICATION_DESTINATION_URL=$MOCK_SERVER_URL

PLATFORM=$(uname -m)
if [ "x86_64" == "$PLATFORM" ]; then
  DOCKER_ROBOT_IMAGE_VERSION=$DOCKER_ROBOT_IMAGE_VERSION-amd64
else
  DOCKER_ROBOT_IMAGE_VERSION=$DOCKER_ROBOT_IMAGE_VERSION-arm64
fi

# Show variables
echo "CAPIF_HOSTNAME = $CAPIF_HOSTNAME"
echo "CAPIF_REGISTER = $CAPIF_REGISTER"
echo "CAPIF_HTTP_PORT = $CAPIF_HTTP_PORT"
echo "CAPIF_HTTPS_PORT = $CAPIF_HTTPS_PORT"
echo "CAPIF_VAULT = $CAPIF_VAULT"
echo "CAPIF_VAULT_PORT = $CAPIF_VAULT_PORT"
echo "CAPIF_VAULT_TOKEN = $CAPIF_VAULT_TOKEN"
echo "TOTAL_USERS=$TOTAL_USERS"
echo "USERNAME_PREFIX=$USERNAME_PREFIX"
echo "USER_PASSWORD=$USER_PASSWORD"
echo "MOCK_SERVER_URL=$MOCK_SERVER_URL"
echo "NOTIFICATION_DESTINATION_URL=$NOTIFICATION_DESTINATION_URL"
echo "DOCKER_ROBOT_IMAGE = $DOCKER_ROBOT_IMAGE:$DOCKER_ROBOT_IMAGE_VERSION"

docker >/dev/null 2>/dev/null
if [[ $? -ne 0 ]]
then
    echo "Docker maybe is not installed. Please check if docker CLI is present."
    exit -1
fi

docker pull $DOCKER_ROBOT_IMAGE:$DOCKER_ROBOT_IMAGE_VERSION || echo "Docker image ($DOCKER_ROBOT_IMAGE:$DOCKER_ROBOT_IMAGE_VERSION) not present on repository"
docker images|grep -Eq '^'$DOCKER_ROBOT_IMAGE'[ ]+[ ]'$DOCKER_ROBOT_IMAGE_VERSION''
if [[ $? -ne 0 ]]
then
    read -p "Robot image is not present. To continue, Do you want to build it? (y/n)" build_robot_image
    if [[ $build_robot_image == "y" ]]
    then
        echo "Building Robot docker image."
        cd $ROBOT_DOCKER_FILE_FOLDER
        docker build --no-cache -t $DOCKER_ROBOT_IMAGE:$DOCKER_ROBOT_IMAGE_VERSION .
        cd $REPOSITORY_BASE_FOLDER
    else
        exit -2
    fi
fi

mkdir -p $RESULT_FOLDER


docker run -ti --rm --network="host" \
    --add-host host.docker.internal:host-gateway \
    --add-host vault:host-gateway \
    --add-host register:host-gateway \
    --add-host mock-server:host-gateway \
    -v $TEST_FOLDER:/opt/robot-tests/tests \
    -v $RESULT_FOLDER:/opt/robot-tests/results ${DOCKER_ROBOT_IMAGE}:${DOCKER_ROBOT_IMAGE_VERSION}  \
    --variable CAPIF_HOSTNAME:$CAPIF_HOSTNAME \
    --variable CAPIF_HTTP_PORT:$CAPIF_HTTP_PORT \
    --variable CAPIF_HTTPS_PORT:$CAPIF_HTTPS_PORT \
    --variable CAPIF_REGISTER:$CAPIF_REGISTER \
    --variable CAPIF_REGISTER_PORT:$CAPIF_REGISTER_PORT \
    --variable CAPIF_VAULT:$CAPIF_VAULT \
    --variable CAPIF_VAULT_PORT:$CAPIF_VAULT_PORT \
    --variable CAPIF_VAULT_TOKEN:$CAPIF_VAULT_TOKEN \
    --variable NOTIFICATION_DESTINATION_URL:$NOTIFICATION_DESTINATION_URL \
    --variable MOCK_SERVER_URL:$MOCK_SERVER_URL \
    --variable TOTAL_USERS:$TOTAL_USERS \
    --variable USERNAME_PREFIX:$USERNAME_PREFIX \
    --variable USER_PASSWORD:$USER_PASSWORD \
    --include create-users

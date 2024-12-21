#!/bin/bash

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
CAPIF_VAULT_TOKEN=dev-only-token

MOCK_SERVER_URL=http://mock-server:9100
NOTIFICATION_DESTINATION_URL=http://mock-server:9100

PLATFORM=$(uname -m)
if [ "x86_64" == "$PLATFORM" ]; then
  DOCKER_ROBOT_IMAGE_VERSION=$DOCKER_ROBOT_IMAGE_VERSION-amd64
else
  DOCKER_ROBOT_IMAGE_VERSION=$DOCKER_ROBOT_IMAGE_VERSION-arm64
fi

echo "CAPIF_HOSTNAME = $CAPIF_HOSTNAME"
echo "CAPIF_REGISTER = $CAPIF_REGISTER"
echo "CAPIF_HTTP_PORT = $CAPIF_HTTP_PORT"
echo "CAPIF_HTTPS_PORT = $CAPIF_HTTPS_PORT"
echo "CAPIF_VAULT = $CAPIF_VAULT"
echo "CAPIF_VAULT_PORT = $CAPIF_VAULT_PORT"
echo "CAPIF_VAULT_TOKEN = $CAPIF_VAULT_TOKEN"
echo "MOCK_SERVER_URL = $MOCK_SERVER_URL"
echo "DOCKER_ROBOT_IMAGE = $DOCKER_ROBOT_IMAGE:$DOCKER_ROBOT_IMAGE_VERSION"

INPUT_OPTIONS=$@
# Check if input is provided
if [ -z "$1" ]; then
    # Set default value if no input is provided
    INPUT_OPTIONS="--include all"
fi

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
    --add-host $CAPIF_HOSTNAME:host-gateway \
    --add-host $CAPIF_REGISTER:host-gateway \
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
    --variable MOCK_SERVER_URL:$MOCK_SERVER_URL $INPUT_OPTIONS

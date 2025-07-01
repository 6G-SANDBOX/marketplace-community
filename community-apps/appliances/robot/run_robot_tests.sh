#!/bin/bash
source "$(dirname "$(readlink -f "$0")")/variables.sh"

TEST_FOLDER=$BASE_DIR/tests
RESULT_FOLDER=$BASE_DIR/results
ROBOT_DOCKER_FILE_FOLDER=$BASE_DIR/tools/robot
SUT_IP=""

echo "DOCKER_ROBOT_IMAGE = $DOCKER_ROBOT_IMAGE:$DOCKER_ROBOT_IMAGE_VERSION"

# If no parameters are provided, display usage information
if [[ $# -eq 0 ]]; then
    echo "No parameters provided. Please provide the IP of the SUT and options."
    echo "Usage: $0 <SUT_IP> [options...]"
    echo "SUT_IP: IP address of the System Under Test (SUT)"
    echo "Options: --include <test_suite> | --exclude <test_suite> | --include all"
    exit 1
else
  if [[ "$1" != --* ]]; then
    SUT_IP="$1"
    echo "IP detected: $SUT_IP"
    shift
  fi
fi

INPUT_OPTIONS=$@
# Check if input is provided
if [ -z "$1" ]; then
    # Set default value if no input is provided
    INPUT_OPTIONS="--include all"
fi

cd $BASE_DIR

# Check if docker is installed
docker >/dev/null 2>/dev/null
if [[ $? -ne 0 ]]
then
    echo "Docker maybe is not installed. Please check if docker CLI is present."
    exit -1
fi

mkdir -p $RESULT_FOLDER

docker run $DOCKER_ROBOT_TTY_OPTIONS --rm --network="host" \
    -v $TEST_FOLDER:/opt/robot-tests/tests \
    -v $RESULT_FOLDER:/opt/robot-tests/results ${DOCKER_ROBOT_IMAGE}:${DOCKER_ROBOT_IMAGE_VERSION} \
    --variable SUT_IP:$SUT_IP $INPUT_OPTIONS

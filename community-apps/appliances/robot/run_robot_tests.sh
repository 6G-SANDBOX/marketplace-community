#!/bin/bash
source $(dirname "$(readlink -f "$0")")/variables.sh

TEST_FOLDER=$BASE_DIR/tests
RESULT_FOLDER=$BASE_DIR/results
ROBOT_DOCKER_FILE_FOLDER=$BASE_DIR/tools/robot

echo "DOCKER_ROBOT_IMAGE = $DOCKER_ROBOT_IMAGE:$DOCKER_ROBOT_IMAGE_VERSION"

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


# docker pull $DOCKER_ROBOT_IMAGE:$DOCKER_ROBOT_IMAGE_VERSION || echo "Docker image ($DOCKER_ROBOT_IMAGE:$DOCKER_ROBOT_IMAGE_VERSION) not present on repository"
# docker images|grep -Eq '^'$DOCKER_ROBOT_IMAGE'[ ]+[ ]'$DOCKER_ROBOT_IMAGE_VERSION''
# if [[ $? -ne 0 ]]
# then
#     read -p "Robot image is not present. To continue, Do you want to build it? (y/n)" build_robot_image
#     if [[ $build_robot_image == "y" ]]
#     then
#         echo "Building Robot docker image."
#         cd $ROBOT_DOCKER_FILE_FOLDER
#         docker build --no-cache -t $DOCKER_ROBOT_IMAGE:$DOCKER_ROBOT_IMAGE_VERSION .
#         cd $BASE_DIR
#     else
#         exit -2
#     fi
# fi

mkdir -p $RESULT_FOLDER

docker run $DOCKER_ROBOT_TTY_OPTIONS -ti --rm --network="host" \
    -v $TEST_FOLDER:/opt/robot-tests/tests \
    -v $RESULT_FOLDER:/opt/robot-tests/results ${DOCKER_ROBOT_IMAGE}:${DOCKER_ROBOT_IMAGE_VERSION} \
    --variable TEST_MESSAGE:"$TEST_MESSAGE" \
    --variable TEST_MESSAGE2:"$TEST_MESSAGE2" $INPUT_OPTIONS

#!/bin/bash

# timestap to use along scripts
export timestamp=$(date +"%Y%m%d_%H%M%S")

# Directories variables setup (no modification needed)
export BASE_DIR=$(dirname "$(readlink -f "$0")")

# Robot Framework variables
export DOCKER_ROBOT_TTY_OPTIONS="-ti"
export REGISTRY_BASE_URL="example.com:5050/one/robot-tests"
export DOCKER_ROBOT_IMAGE="${REGISTRY_BASE_URL}/robot-tests-image"
export DOCKER_ROBOT_IMAGE_VERSION="1.0"
export PRIVATE_KEY_FILE="${BASE_DIR}/tests/certs/id_rsa"

# Configuration needed before use installation/uninstallation scripts
export TEST_MESSAGE="This"
export TEST_MESSAGE2="This2"

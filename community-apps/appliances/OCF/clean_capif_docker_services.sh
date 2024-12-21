#!/bin/bash

# Directories variables setup (no modification needed)
export SERVICES_DIR=$(dirname "$(readlink -f "$0")")
export CAPIF_BASE_DIR=$(dirname "$SERVICES_DIR")

help() {
  echo "Usage: $1 <options>"
  echo "       -c : Clean capif services"
  echo "       -v : Clean vault service"
  echo "       -r : Clean register service"
  echo "       -m : Clean monitoring service"
  echo "       -s : Clean Robot Mock service"
  echo "       -a : Clean all services"
  echo "       -h : show this help"
  exit 1
}

if [[ $# -lt 1 ]]
then
  echo "You must specify an option before run script."
  help
fi

FILES=()
echo "${FILES[@]}"

# Read params
while getopts "cvrahms" opt; do
  case $opt in
    c)
      echo "Remove Capif services"
      FILES+=("$SERVICES_DIR/docker-compose-capif.yml")
      ;;
    v)
      echo "Remove vault service"
      FILES+=("$SERVICES_DIR/docker-compose-vault.yml")
      ;;
    r)
      echo "Remove register service"
      FILES+=("$SERVICES_DIR/docker-compose-register.yml")
      ;;
    m)
      echo "Remove monitoring service"
      FILES+=("$SERVICES_DIR/monitoring/docker-compose.yml")
      ;;
    s)
      echo "Robot Mock Server"
      FILES+=("$SERVICES_DIR/docker-compose-mock-server.yml")
      ;;
    a)
      echo "Remove all services"
      FILES=("$SERVICES_DIR/docker-compose-capif.yml" "$SERVICES_DIR/docker-compose-vault.yml" "$SERVICES_DIR/docker-compose-register.yml" "$SERVICES_DIR/docker-compose-mock-server.yml" "$SERVICES_DIR//monitoring/docker-compose.yml")
      ;;
    h)
      help
      ;;
    \?)
      echo "Not valid option: -$OPTARG" >&2
      help
      exit 1
      ;;
    :)
      echo "The -$OPTARG option requires an argument." >&2
      help
      exit 1
      ;;
  esac
done
echo "after check"
echo "${FILES[@]}"

for FILE in "${FILES[@]}"; do
  echo "Executing 'docker compose down' for file $FILE"
  CAPIF_PRIV_KEY=$CAPIF_PRIV_KEY_BASE_64 DUID=$DUID DGID=$DGID MONITORING=$MONITORING_STATE LOG_LEVEL=$LOG_LEVEL docker compose -f "$FILE" down --rmi all
  status=$?
    if [ $status -eq 0 ]; then
        echo "*** Removed Service from $FILE ***"
    else
        echo "*** Some services of $FILE failed on clean ***"
    fi
done

docker network rm capif-network

docker volume prune --all --force

echo "Clean complete."

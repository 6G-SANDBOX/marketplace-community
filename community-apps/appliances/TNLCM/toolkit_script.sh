#!/bin/bash
set -o errexit -o pipefail
source /var/run/one-context/one_env

max_attempts=10
attempt=0

echo "Updating JENKINS_TOKEN in onegate"
while [ -z "$jenkins_token" ] && [ $attempt -lt $max_attempts ]; do
    jenkins_id="$(onegate service show --json | jq -r '.SERVICE.roles[] | select(.name == "jenkins").nodes[].deploy_id')"
    jenkins_token="$(onegate vm show $jenkins_id --json | jq -r .VM.USER_TEMPLATE.JENKINS_TOKEN)"

    if [ -z "$jenkins_token" ]; then
        echo "Attempt $((attempt+1)): jenkins_token not available. Retry..."
        attempt=$((attempt+1))
        sleep 5
    fi
done


if [ -n "$jenkins_token" ]; then
    echo "Writing jenkins_token ${jenkins_token} into the .env file"
    sed -i "s%^JENKINS_TOKEN=.*%JENKINS_TOKEN=${jenkins_token}%" /opt/TNLCM_BACKEND/.env
    echo "Substitution was successful. Restarting TNLCM backend..."
    systemctl restart tnlcm-backend.service
else
    echo "Error: jenkins_token could not be fetched after $max_attempts attempts."
fi

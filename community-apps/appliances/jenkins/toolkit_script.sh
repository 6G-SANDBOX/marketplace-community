#!/bin/bash
set -o errexit -o pipefail
source /var/run/one-context/one_env

jenkins_id="$(onegate vm show -j | jq -r '.VM.ID')"
minio_id="$(onegate service show --json | jq -r '.SERVICE.roles[] | select(.name=="minio") .nodes[0].vm_info.VM.ID')"

echo "Updating JENKINS_TOKEN in onegate"
onegate vm update "${jenkins_id}" --data JENKINS_TOKEN="$(cat /var/lib/jenkins/consult_me/jenkins_tnlcm_token)"
echo "Updating SSH_KEY in onegate"
onegate vm update "${jenkins_id}" --data SSH_KEY="$(cat /var/lib/jenkins/consult_me/id_ed25519.pub)"

echo "Resizing MinIO in onegate"
/usr/local/bin/onevm disk-resize "${minio_id}" 0 10G --user "${ONEAPP_JENKINS_OPENNEBULA_USERNAME}" --password "${ONEAPP_JENKINS_OPENNEBULA_PASSWORD}" --endpoint "${ONEAPP_JENKINS_OPENNEBULA_ENDPOINT}"

echo "DONE"

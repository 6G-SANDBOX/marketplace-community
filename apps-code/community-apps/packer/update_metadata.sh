#!/bin/bash

### Define first set of execution variables
LOGFILE=packer/update_metadata.log
APP_NAME=${1}       # e.g. jenkins
# APP_VER=${2}      # e.g. 11      I don't use version for appliances

APPLIANCE_ORG=${3}                                  # e.g. export/jenkins.qcow2
APPLIANCE_DST=${DIR_APPLIANCES}/${APP_NAME}.qcow2   # e.g. /var/lib/one/6gsandbox-marketplace/jenkins.qcow2

METADATA_ORG=../../appliances/${APP_NAME}/${APP_NAME}.yaml  # e.g. ../appliances/jenkins/jenkins.yaml
METADATA_DST=${DIR_METADATA}/${APP_NAME}.yaml               # e.g. /opt/marketplace-community/marketplace/appliances/jenkins.yaml

if [ -f "${APPLIANCE_DST}" ]; then
    test -d "${DIR_APPLIANCES}/backup/" || mkdir -p "${DIR_APPLIANCES}/backup/"
    BACKUP=${DIR_APPLIANCES}/backup/${APP_NAME}-$(stat -c %y "${APPLIANCE_DST}" | awk '{print $1}' | sed 's/-//g').qcow2   # e.g. /var/lib/one/6gsandbox-marketplace/backup/jenkins-20240723.qcow2
else
    # If there is no previous image, there is nothing to backup
    BACKUP=None
fi




echo "------------------New build--------------------------" >> ${LOGFILE}

### Ensure yq is installed
install_yq()
{
    sudo apt-get update && sudo apt-get install -y wget
    sudo wget https://github.com/mikefarah/yq/releases/download/v4.44.2/yq_linux_amd64 -O /usr/bin/yq
    sudo chmod +x /usr/bin/yq
    echo "Command yq installed successfully" >> ${LOGFILE}
}

if ! command -v yq &> /dev/null
then
    echo "<WARNING>: command yq was not found. Installing at /usr/bin/yq" >> ${LOGFILE}
    install_yq
fi

if [ ! -f "${APPLIANCE_ORG}" ]; then
    echo "<ERROR>: A newly generated image was not found at ${APPLIANCE_ORG}." >> ${LOGFILE}
    exit 1
fi

### Define second set of execution variables
FULL_NAME="${APPLIANCE_PREFIX:+$APPLIANCE_PREFIX }$(cat "${METADATA_ORG}" | yq '.name')"  # e.g. 6G-Sandbox bastion
SW_VERSION=$(cat "metadata/${APP_NAME}.yaml" | yq '.software_version')                    # e.g. v0.4.0  


{
  echo "APP_NAME=\"${APP_NAME}\""
  echo "FULL_NAME=\"${FULL_NAME}\""
  echo "SW_VERSION=\"${SW_VERSION}\""
  echo "APPLIANCE_ORG=\"${APPLIANCE_ORG}\""
  echo "APPLIANCE_DST=\"${APPLIANCE_DST}\""
  echo "BACKUP=\"${BACKUP}\""
  echo "METADATA_ORG=\"${METADATA_ORG}\""
  echo "METADATA_DST=\"${METADATA_DST}\""
} >> ${LOGFILE}


### Move previous appliance to backup
if [ -f "${APPLIANCE_DST}" ]; then
    mv "${APPLIANCE_DST}" "${BACKUP}"
fi
### Move actual appliance to destination
mv "${APPLIANCE_ORG}" "${APPLIANCE_DST}"


### Calculate build variables
IMAGE_EPOCH_TIMESTAMP="$(stat -c %W "${APPLIANCE_DST}")"                        # e.g. 1746523232
IMAGE_READABLE_TIMESTAMP=$(date +"%Y%m%d-%H%M" -d @"${IMAGE_EPOCH_TIMESTAMP}")  # e.g. 20250506-1120
if [ -n "${SW_VERSION}" ]; then         # Set build version with sw_version and build timestamp
    BUILD_VERSION=${SW_VERSION}-${IMAGE_READABLE_TIMESTAMP}  # e.g. v0.4.0-20250506-1120
else
    BUILD_VERSION=${IMAGE_READABLE_TIMESTAMP}                # e.g. 20250506-1120
fi
IMAGE_NAME="${FULL_NAME} ${BUILD_VERSION}"
IMAGE_URL="${URL_APPLIANCES}/${APP}.qcow2"
IMAGE_SIZE="$(qemu-img info "${APPLIANCE_DST}" | awk '/virtual size:/ {print $5}' | sed 's/[^0-9]*//g')"
IMAGE_CHK_MD5="$(md5sum "${APPLIANCE_DST}" | cut -d' ' -f1)"
IMAGE_CHK_SHA256="$(sha256sum "${APPLIANCE_DST}" | cut -d' ' -f1)"


### Log build variables
{
  echo "BUILD_VERSION=\"${BUILD_VERSION}\""
  echo "IMAGE_NAME=\"${IMAGE_NAME}\""
  echo "IMAGE_URL=\"${IMAGE_URL}\""
  echo "IMAGE_TIMESTAMP=\"${IMAGE_EPOCH_TIMESTAMP}\""
  echo "IMAGE_SIZE=\"${IMAGE_SIZE}\""
  echo "IMAGE_CHK_MD5=\"${IMAGE_CHK_MD5}\""
  echo "IMAGE_CHK_SHA256=\"${IMAGE_CHK_SHA256}\""
} >> ${LOGFILE}


### Write final metadata file
test -d "${DIR_METADATA}/" || mkdir -p "${DIR_METADATA}/"
cat "${METADATA_ORG}" | yq eval "
  .name = \"${FULL_NAME}\" |
  .version = \"${BUILD_VERSION}\" |
  .creation_time = \"${IMAGE_EPOCH_TIMESTAMP}\" |
  .images[0].name = \"${IMAGE_NAME}\" |
  .images[0].url = \"${IMAGE_URL}\" |
  .images[0].size = \"${IMAGE_SIZE}\" |
  .images[0].checksum.md5 = \"${IMAGE_CHK_MD5}\" |
  .images[0].checksum.sha256 = \"${IMAGE_CHK_SHA256}\"
" > "${METADATA_DST}"

### Reload marketplace with the new file
sleep 10
systemctl restart appmarket-simple.service



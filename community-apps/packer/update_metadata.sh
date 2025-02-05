#!/bin/bash

### Verify yq is installed
if ! command -v yq &> /dev/null
then
    install_yq
fi


LOGFILE=packer/update_metadata.log
APP=${1}                                        # e.g. debian
APP_VER=${2}                                    # e.g. 11
if [ -n "${APP_VER}" ]; then
    APP=${APP}${APP_VER}                        # e.g. debian11 
fi
FULL_NAME=$(cat "metadata/${APP}.yaml" | yq '.name')            # 6G-Sandbox bastion
SW_VER=$(cat "metadata/${APP}.yaml" | yq '.software_version')   # v0.4.0  
ORIGIN=${3}                                     # e.g. export/debian11
DESTINATION=${DIR_APPLIANCES}/${APP}.qcow2      # e.g. /var/lib/one/6gsandbox-marketplace/debian11.qcow2
if [ -f "${DESTINATION}" ]; then
    mkdir "${DIR_APPLIANCES}/backup/"
    BACKUP=${DIR_APPLIANCES}/backup/${APP}-$(stat -c %y "${DESTINATION}" | awk '{print $1}' | sed 's/-//g').qcow2   # e.g. /var/lib/one/6gsandbox-marketplace/backup/debian11-20240723.qcow2
else
    BACKUP=None
fi
METADATA=${DIR_METADATA}/${APP}.yaml             # e.g. /opt/marketplace-community/marketplace/appliances/debian11.yaml




### Log loaded inputs from enviromental variables
{
  echo "------------------New build--------------------------"
  echo "APP=${APP}"
  echo "APP_VER=${APP_VER}"
  echo "SW_VER=${SW_VER}"
  echo "ORIGIN=${ORIGIN}"
  echo "VERSION=${VERSION}"
  echo "DESTINATION=${DESTINATION}"
  echo "BACKUP=${BACKUP}"
  echo "METADATA=${METADATA}"
} >> ${LOGFILE}


### Backup previous image
if [ -f "${DESTINATION}" ]; then
    mv "${DESTINATION}" "${BACKUP}"
fi
mv "${ORIGIN}" "${DESTINATION}"


### Set appliance version with sw_version and build timestamp
if [ -n "${SW_VER}" ]; then
    VERSION=${SW_VER}-$(date +"%Y%m%d-%H%M")          # e.g. v0.4.0-20240723-1016
else
    VERSION=$(date +"%Y%m%d-%H%M")                    # e.g. 20240723-1016
fi

IMAGE_NAME="${FULL_NAME}-${VERSION}"
IMAGE_TIMESTAMP="$(stat -c %W "${DESTINATION}")"
IMAGE_SIZE="$(qemu-img info "${DESTINATION}" | awk '/virtual size:/ {print $5}' | sed 's/[^0-9]*//g')"
IMAGE_CHK_MD5="$(md5sum "${DESTINATION}" | cut -d' ' -f1)"
IMAGE_CHK_SHA256="$(sha256sum "${DESTINATION}" | cut -d' ' -f1)"

{
  echo "VERSION=${VERSION}"
  echo "IMAGE_NAME=${IMAGE_NAME}"
  echo "IMAGE_TIMESTAMP=${IMAGE_TIMESTAMP}"
  echo "IMAGE_SIZE=${IMAGE_SIZE}"
  echo "IMAGE_CHK_MD5=${IMAGE_CHK_MD5}"
  echo "IMAGE_CHK_SHA256=${IMAGE_CHK_SHA256}"
} >> ${LOGFILE}

# cp "metadata/${APP}.yaml"  "${METADATA}"
yq eval -i "
  .version = \"${VERSION}\" |
  .creation_time = \"${IMAGE_TIMESTAMP}\" |
  .images[0].name = \"${IMAGE_NAME}\" |
  .images[0].size = \"${IMAGE_SIZE}\" |
  .images[0].checksum.md5 = \"${IMAGE_CHK_MD5}\" |
  .images[0].checksum.sha256 = \"${IMAGE_CHK_SHA256}\"
" "${METADATA}"
# cat "${METADATA}" | yq ".version = \"${VERSION}\"" | sponge "${METADATA}"
# cat "${METADATA}" | yq ".creation_time = \"${IMAGE_TIMESTAMP}\"" | sponge "${METADATA}"
# cat "${METADATA}" | yq ".images[0].size = \"${IMAGE_SIZE}\"" | sponge "${METADATA}"
# cat "${METADATA}" | yq ".images[0].checksum.md5 = \"${IMAGE_CHK_MD5}\"" | sponge "${METADATA}"
# cat "${METADATA}" | yq ".images[0].checksum.sha256 = \"${IMAGE_CHK_SHA256}\"" | sponge "${METADATA}"

# sleep 5
# systemctl restart appmarket-simple.service




# TODO que VERSION tome "software_version"

# TODO que image_name tome name+version
# .images[0].name = \"${IMAGE_NAME}\" |



install_yq()
{
    echo "------------------SETUP--------------------------" >> ${LOGFILE}
    echo "Command yq is not present in the system. Installing" >> ${LOGFILE}
    sudo apt-get update && sudo apt-get install -y wget
    sudo wget https://github.com/mikefarah/yq/releases/download/v4.44.2/yq_linux_amd64 -O /usr/bin/yq
    sudo chmod +x /usr/bin/yq
    echo "Command yq installed successfully" >> ${LOGFILE}
}
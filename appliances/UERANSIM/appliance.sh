#!/usr/bin/env bash

set -o errexit -o pipefail

# ------------------------------------------------------------------------------
# Contextualization and global variables
# ------------------------------------------------------------------------------

### EDIT: Undefined variables wont be replaced in the target file.
# ONEAPP_UERANSIM_RUN_GNB="${ONEAPP_UERANSIM_RUN_GNB:-NO}"
# ONEAPP_UERANSIM_GNB_AMF_IP="${ONEAPP_UERANSIM_GNB_AMF_IP:-127.0.0.5}"
# ONEAPP_UERANSIM_GNB_TAC="${ONEAPP_UERANSIM_GNB_TAC:-1}"
# ONEAPP_UERANSIM_GNB_MCC="${ONEAPP_UERANSIM_GNB_MCC:-999}"
# ONEAPP_UERANSIM_GNB_MNC="${ONEAPP_UERANSIM_GNB_MNC:-70}"
# ONEAPP_UERANSIM_GNB_SLICES_SST="${ONEAPP_UERANSIM_GNB_SLICES_SST:-1}"
# ONEAPP_UERANSIM_GNB_SLICES_SD="${ONEAPP_UERANSIM_GNB_SLICES_SD:-000001}"
# ONEAPP_UERANSIM_RUN_UE="${ONEAPP_UERANSIM_RUN_UE:-NO}"
# ONEAPP_UERANSIM_UE_GNBSEARCHLIST="${ONEAPP_UERANSIM_UE_GNBSEARCHLIST:-localhost}"
# ONEAPP_UERANSIM_UE_MCC="${ONEAPP_UERANSIM_UE_MCC:-999}"
# ONEAPP_UERANSIM_UE_MNC="${ONEAPP_UERANSIM_UE_MNC:-70}"
# ONEAPP_UERANSIM_UE_MSIN="${ONEAPP_UERANSIM_UE_MSIN:-imsi-0000000001}"
# ONEAPP_UERANSIM_UE_KEY="${ONEAPP_UERANSIM_UE_KEY:-465B5CE8B199B49FAA5F0A2EE238A6BC}"
# ONEAPP_UERANSIM_UE_OPC="${ONEAPP_UERANSIM_UE_OPC:-E8ED289DEBA952E4283B54E88E6183CA}"
# ONEAPP_UERANSIM_UE_SESSION_APN="${ONEAPP_UERANSIM_UE_SESSION_APN:-internet}"
# ONEAPP_UERANSIM_UE_SESSION_SST="${ONEAPP_UERANSIM_UE_SESSION_SST:-1}"
# ONEAPP_UERANSIM_UE_SESSION_SD="${ONEAPP_UERANSIM_UE_SESSION_SD:-000001}"
# ONEAPP_UERANSIMUE_HNET_PUBKEY="${ONEAPP_UERANSIMUE_HNET_PUBKEY:-5a8d38864820197c3394b92613b20b91633cbd897119273bf8e4a6f4eec0a650}"
# ONEAPP_UERANSIMUE_HNET_PUBKEY_ID="${ONEAPP_UERANSIMUE_HNET_PUBKEY_ID:-1}"
# ONEAPP_UERANSIMUE_SUCI_PROT="${ONEAPP_UERANSIMUE_SUCI_PROT:-0}"

DEP_PKGS="libsctp-dev lksctp-tools iproute2 wget moreutils"


# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# Mandatory Functions
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------

service_install()
{
    export DEBIAN_FRONTEND=noninteractive
    systemctl stop unattended-upgrades

    install_pkg_deps

    define_services

    postinstall_cleanup

    msg info "INSTALLATION FINISHED"

    return 0
}

service_configure()
{
    export DEBIAN_FRONTEND=noninteractive

    LOCAL_IP=$(hostname -I | awk '{print $1}')

    config_gnb

    config_ue

    msg info "CONFIGURATION FINISHED"
    return 0
}


service_bootstrap()
{
    export DEBIAN_FRONTEND=noninteractive

    if [ -n "${ONEAPP_UERANSIM_RUN_GNB}" ] && [ "${ONEAPP_UERANSIM_RUN_GNB}" = "YES" ]; then
        if ! systemctl enable --now ueransim-gnb.service ; then
            msg error "Error starting ueransimb-gnb.service"
            exit 1
        else
            msg info "ueransimb-gnb.service was started"
            sleep 15    # Force wait time to avoid career condition which provokes a Duplicated Request to the UPF (cannot handle PFCP message type[50] (../src/upf/pfcp-sm.c:150))
        fi
    fi

    if [ -n "${ONEAPP_UERANSIM_RUN_UE}" ] && [ "${ONEAPP_UERANSIM_RUN_UE}" = "YES" ]; then
        if ! systemctl enable --now ueransim-ue.service ; then
            msg error "Error starting ueransimb-ue.service"
            exit 1
        else
            msg info "ueransimb-ue.service was started"
        fi
    fi

    msg info "BOOTSTRAP FINISHED"
    return 0
}


# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# Function Definitions
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------

install_pkg_deps()
{
    msg info "Run apt-get update"
    apt-get update

    msg info "Install required .deb packages"
    wait_for_dpkg_lock_release
    if ! apt-get install -y ${DEP_PKGS} ; then
        msg error "Package(s) installation failed"
        exit 1
    fi

    msg info "Download yq binary"
    if ! wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq ; then
        msg error "yq binary download failed"
        exit 1
    fi
    chmod +x /usr/bin/yq
}

define_services()
{
    msg info "Define ueransim-gnb systemd service"
    cat > /etc/systemd/system/ueransim-gnb.service << EOF
[Unit]
Description=UERANSIM gNB Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/nr-gnb -c /etc/ueransim/open5gs-gnb.yaml
Restart=always
PIDFile=/run/ueransim-gnb.pid

[Install]
WantedBy=multi-user.target
EOF

    msg info "Define ueransim-ue systemd service"
    cat > /etc/systemd/system/ueransim-ue.service << EOF
[Unit]
Description=UERANSIM UE Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/nr-ue -c /etc/ueransim/open5gs-ue.yaml
Restart=always
PIDFile=/run/ueransim-ue.pid

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
}


config_gnb()
{
    GNB_ORIGINAL_CONFIG_FILE=/etc/ueransim/open5gs-gnb-original.yaml
    GNB_CONFIG_FILE=/etc/ueransim/open5gs-gnb.yaml
    GNB_MAPPINGS_FILE=/etc/one-appliance/service.d/gnb-mappings.json

    msg info "GNB_CONFIGURATION: Create file ${GNB_CONFIG_FILE} and replace its variables"
    cp ${GNB_ORIGINAL_CONFIG_FILE} ${GNB_CONFIG_FILE}

    yq_replacements "${GNB_CONFIG_FILE}" "${GNB_MAPPINGS_FILE}"
}

config_ue()
{
    UE_ORIGINAL_CONFIG_FILE=/etc/ueransim/open5gs-ue-original.yaml
    UE_CONFIG_FILE=/etc/ueransim/open5gs-ue.yaml
    UE_MAPPINGS_FILE=/etc/one-appliance/service.d/ue-mappings.json

    msg info "UE_CONFIGURATION: Create file ${UE_CONFIG_FILE} and replace its variables"
    cp ${UE_ORIGINAL_CONFIG_FILE} ${UE_CONFIG_FILE}

    if [ -n "${ONEAPP_UERANSIM_UE_MCC}" ] && [ -n "${ONEAPP_UERANSIM_UE_MNC}" ] && [ -n "${ONEAPP_UERANSIM_UE_MSIN}" ]; then
        IMSI="${ONEAPP_UERANSIM_UE_MCC}${ONEAPP_UERANSIM_UE_MNC}${ONEAPP_UERANSIM_UE_MSIN}"
        if [ ${#IMSI} -gt 15 ]; then
            msg warning "IMSI (MCC+MNC+MSIN) exceeds 15 characters (${#IMSI}). Truncating..."
            IMSI="${IMSI:0:15}"
        fi
        SUPI="imsi-${IMSI}"
    fi

    if [ -n "${ONEAPP_UERANSIM_UE_GNBSEARCHLIST}" ]; then
        if [ "${ONEAPP_UERANSIM_UE_GNBSEARCHLIST}" == "localhost" ]; then
            GNBSEARCHLIST="${LOCAL_IP}"
        else
            GNBSEARCHLIST="${ONEAPP_UERANSIM_UE_GNBSEARCHLIST}"
        fi
    fi

    yq_replacements "${UE_CONFIG_FILE}" "${UE_MAPPINGS_FILE}"
}


yq_replacements()
{
    local config_file="${1}"
    local mappings_file="${2}"

    for dict in $(jq -c '.' "${mappings_file}"); do
        path=$(echo "${dict}" | jq -r '.path')
        env_var=$(echo "${dict}" | jq -r '.env_var')
        type=$(echo "${dict}" | jq -r '.type')

        value="${!env_var}"
        if [ -z "$value" ]; then
            msg info "    Variable ${env_var} is not defined. Skipping..."
            continue
        fi

        case "${type}" in
            int|bool)
                msg info "    Change variable ${env_var} with value ${value} (${type})"
                yq -i "${path} = ${value}" "${config_file}"
                ;;
            string)
                msg info "    Change variable ${env_var} with value '${value}' (${type})"
                yq -i "${path} = \"${value}\"" "${config_file}"
                ;;
            list)
                msg info "    Change variable ${env_var} (${type})"
                yq -i "${path} = []" "${config_file}"

                IFS=',' read -ra item_list <<< "${value}"
                for index in "${!item_list[@]}"; do
                    item="${item_list[${index}]}"
                    msg info "        Append item [${index}]: ${item}"
                    yq -i "${path}[${index}] = \"${item}\"" "${config_file}"
                done
                ;;
            *)
                msg warning "    Variable ${env_var} has unknown type: (${type}). Skipping..."
                ;;
        esac
    done
}


wait_for_dpkg_lock_release()
{
  local lock_file="/var/lib/dpkg/lock-frontend"
  local timeout=600
  local interval=5

  for ((i=0; i<timeout; i+=interval)); do
    if ! lsof "${lock_file}" &>/dev/null; then
      return 0
    fi
    msg info "Could not get lock ${lock_file} due to unattended-upgrades. Retrying in ${interval} seconds..."
    sleep "${interval}"
  done

  msg error "Error: 10m timeout without ${lock_file} being released by unattended-upgrades"
  exit 1
}

postinstall_cleanup()
{
    msg info "Delete cache and stored packages"
    wait_for_dpkg_lock_release
    apt-get autoclean
    apt-get autoremove
    rm -rf /var/lib/apt/lists/*
}

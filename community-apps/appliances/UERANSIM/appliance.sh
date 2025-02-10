#!/usr/bin/env bash

set -o errexit -o pipefail

# ------------------------------------------------------------------------------
# Contextualization and global variables
# ------------------------------------------------------------------------------

GNB_MCC="${GNB_MCC:-999}"
GNB_MNC="${GNB_MNC:-70}"
GNB_SLICES_SD="${GNB_SLICES_SD:-000001}"
GNB_SLICES_SST="${GNB_SLICES_SST:-1}"
GNB_TAC="${GNB_TAC:-1}"
UE_CONFIGURED_NSSAI_SST="${UE_CONFIGURED_NSSAI_SST:-1}"
UE_DEFAULT_NSSAI_SD="${UE_DEFAULT_NSSAI_SD:-000001}"
UE_DEFAULT_NSSAI_SST="${UE_DEFAULT_NSSAI_SST:-1}"
UE_GNBSEARCHLIST="${UE_GNBSEARCHLIST:-127.0.0.1}"
UE_KEY="${UE_KEY:-465B5CE8B199B49FAA5F0A2EE238A6BC}"
UE_MCC="${UE_MCC:-999}"
UE_MNC="${UE_MNC:-70}"
UE_OP="${UE_OP:-E8ED289DEBA952E4283B54E88E6183CA}"
UE_SESSION_APN="${UE_SESSION_APN:-internet}"
UE_SESSION_SST="${UE_SESSION_SST:-1}"
UE_SUPI="${UE_SUPI:-imsi-999700000000001}"

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

    # packages
    install_pkg_deps

    # yaml query
    install_yq

    # services
    define_services

    # cleanup
    postinstall_cleanup

    msg info "INSTALLATION FINISHED"

    return 0
}


# ------------------------------------------------------------------------------
# Configuration Stage => Senerates gNodeB and UE config files
# ------------------------------------------------------------------------------
service_configure()
{
    export DEBIAN_FRONTEND=noninteractive

    # Environmental values and the yaml paths to change
    declare -A gnb_variables=(
        [".mcc"]="GNB_MCC"
        [".mnc"]="GNB_MNC"
        [".tac"]="GNB_TAC"
        [".linkIp"]="GNB_LINKIP"
        [".ngapIp"]="GNB_NGAPIP"
        [".gtpIp"]="GNB_GTPIP"
        [".amfConfigs[0].address"]="GNB_AMF_ADDRESS"
        [".slices[0].sst"]="GNB_SLICES_SST"
        [".slices[0].sd"]="GNB_SLICES_SD"
    )
    declare -A ue_variables=(
        [".supi"]="UE_SUPI"
        [".mcc"]="UE_MCC"
        [".mnc"]="UE_MNC"
        [".key"]="UE_KEY"
        [".op"]="UE_OP"
        [".gnbSearchList[0]"]="UE_GNBSEARCHLIST"
        [".sessions[0].apn"]="UE_SESSION_APN"
        [".sessions[0].slice.sst"]="UE_SESSION_SST"
        [".sessions[0].slice.sd"]="UE_SESSION_SD"
        [".configured-nssai[0].sst"]="UE_CONFIGURED_NSSAI_SST"
        [".configured-nssai[0].sd"]="UE_CONFIGURED_NSSAI_SD"
        [".default-nssai[0].sst"]="UE_DEFAULT_NSSAI_SST"
        [".default-nssai[0].sd"]="UE_DEFAULT_NSSAI_SD"
    )

    ### gNB local IP and UE gnbSearchList will be by default the address from eth0
    GNB_LINKIP=$(hostname -I | awk '{print $1}')
    GNB_NGAPIP=$(hostname -I | awk '{print $1}')
    GNB_GTPIP=$(hostname -I | awk '{print $1}')
    if [ -z "${UE_GNBSEARCHLIST}" ]; then
      UE_GNBSEARCHLIST=$(hostname -I | awk '{print $1}')
    fi

    config_gnb

    config_ue

    amf_route

    msg info "CONFIGURATION FINISHED"
    return 0
}

# Will start gNB and UE
service_bootstrap()
{
    export DEBIAN_FRONTEND=noninteractive

    if [ -n "${RUN_GNB}" ] && [ "${RUN_GNB}" = "YES" ]; then
        if ! systemctl enable --now ueransim-gnb.service ; then
            msg error "Error starting ueransimb-gnb.service"
            exit 1
        else
            msg info "ueransimb-gnb.service was started"
        fi
    fi

    sleep 5

    if [ -n "${RUN_UE}" ] && [ "${RUN_UE}" = "YES" ]; then
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
}

install_yq()
{
    msg info "Download yq binary"
    if ! wget https://github.com/mikefarah/yq/releases/download/v4.44.2/yq_linux_amd64 -O /usr/bin/yq ; then
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
    gnb_config_bak=/etc/ueransim/open5gs-gnb-bak.yaml
    gnb_config=/etc/ueransim/open5gs-gnb.yaml

    msg info "Modify variables from file ${gnb_config}"
    cp ${gnb_config_bak} ${gnb_config}

    for path in "${!gnb_variables[@]}"; do
        yq_replacements_chain ${path} ${gnb_variables[${path}]} ${gnb_config}
    done
}

config_ue()
{
    ue_config_bak=/etc/ueransim/open5gs-ue-bak.yaml
    ue_config=/etc/ueransim/open5gs-ue.yaml

    msg info "Modify variables from file ${ue_config}"
    cp ${ue_config_bak} ${ue_config}

    for path in "${!ue_variables[@]}"; do
        yq_replacements_chain ${path} ${ue_variables[${path}]} ${ue_config}
    done
}

yq_replacements_chain()
{
    local path="$1"
    local value="$2"
    local configfile="$3"

    if [ -z "${!value}" ]; then
        msg info "    Variable ${value} not defined"
    else
        cat ${configfile} | yq "${path} = \"${!value}\"" | sponge ${configfile}
        msg info "    Variable ${value} succesfully modified"
    fi
}

amf_route()
{
    if [ -n "${ONEKE_VNF}" ] && [ -n "${GNB_AMF_ADDRESS}" ]; then
        oneke_subnet=$(echo ${GNB_AMF_ADDRESS} | cut -d '.' -f 1-3).0/24
        line="ExecStartPre=/usr/sbin/ip route replace ${oneke_subnet} via ${ONEKE_VNF}"

        msg info "Configure routing to the AMF from the gnb service file"
        sed -i "/^ExecStart=/i ${line}" "/etc/systemd/system/ueransim-gnb.service"
    else
        msg info "Either the ONEKE_VNF=${ONEKE_VNF} or the GNB_AMF_ADDRESS=${GNB_AMF_ADDRESS} are not defined so no routing to the AMF has been configured in the gnb service file"
    fi
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
    apt-get autoclean
    apt-get autoremove
    rm -rf /var/lib/apt/lists/*
}

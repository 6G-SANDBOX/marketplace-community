#!/usr/bin/env bash

set -o errexit -o pipefail

# ------------------------------------------------------------------------------
# Appliance metadata
# ------------------------------------------------------------------------------

ONE_SERVICE_NAME='UERANSIM'
ONE_SERVICE_VERSION='3.2.6'   #latest
ONE_SERVICE_BUILD=$(date +%s)
ONE_SERVICE_SHORT_DESCRIPTION='UERANSIM 5G gNB & UE simulator'
ONE_SERVICE_DESCRIPTION=$(cat <<EOF
This appliance installs the latest version of [UERANSIM](https://github.com/aligungr/UERANSIM), the open source state-of-the-art 5G UE and RAN (gNodeB) simulator. UE and RAN can be considered as a 5G mobile phone and a base station in basic terms. The project can be used for testing 5G Core Network and studying 5G System.

The image is based on an Ubuntu 22.04 cloud image with the OpenNebula [contextualization package](http://docs.opennebula.io/6.6/management_and_operations/references/kvm_contextualization.html).

After deploying the appliance, check the status of the deployment in /etc/one-appliance/status. You chan check the appliance logs in /var/log/one-appliance/.
EOF
)

ONE_SERVICE_RECONFIGURABLE=true


# ------------------------------------------------------------------------------
# List of contextualization parameters
# ------------------------------------------------------------------------------
ONE_SERVICE_PARAMS=(
    'GNB_AMF_ADDRESS'         'configure' 'gNB AMF IP Address'                                                                                  'O|text'
    'GNB_MCC'                 'configure' 'gNB Mobile Country Code value'                                                                       'O|text'
    'GNB_MNC'                 'configure' 'gNB Mobile Network Code value (2 or 3 digits)'                                                       'O|text'
    'GNB_TAC'                 'configure' 'gNB Tracking Area Code'                                                                              'O|text'
    'GNB_SLICES_SD'           'configure' 'gNB SD of supported S-NSSAI'                                                                         'O|text'
    'GNB_SLICES_SST'          'configure' 'gNB SST of supported S-NSSAI'                                                                        'O|text'
    'ONEKE_VNF'               'configure' 'If specified, IP address where the gNB will route the traffic in order to reach the gnb_amf_address' 'O|text'
    'RUN_GNB'                 'configure' 'Whether to start the gNB service or not'                                                             'M|boolean'
    'RUN_UE'                  'configure' 'Whether to start the UE service or not'                                                              'M|boolean'
    'UE_CONFIGURED_NSSAI_SD'  'configure' 'UE SD of NSSAI configured by HPLMN'                                                                  'O|text'
    'UE_CONFIGURED_NSSAI_SST' 'configure' 'UE SST of NSSAI configured by HPLMN'                                                                 'O|text'
    'UE_DEFAULT_NSSAI_SD'     'configure' 'UE SD of default Configured NSSAI'                                                                   'O|text'
    'UE_DEFAULT_NSSAI_SST'    'configure' 'UE SST of default Configured NSSAI'                                                                  'O|text'
    'UE_GNBSEARCHLIST'        'configure' 'UE comma separated list of gNB IP addresses for Radio Link Simulation'                               'O|text'
    'UE_KEY'                  'configure' 'UE permanent subscription key'                                                                       'O|text'
    'UE_MCC'                  'configure' 'UE Mobile Country Code value of HPLMN'                                                               'O|text'
    'UE_MNC'                  'configure' 'UE Mobile Network Code value of HPLMN (2 or 3 digits)'                                               'O|text'
    'UE_OP'                   'configure' 'UE Operator code (OP or OPC)'                                                                        'O|text'
    'UE_SESSION_APN'          'configure' 'UE APN of initial PDU session to be stablished'                                                      'O|text'
    'UE_SESSION_SD'           'configure' 'UE SD of initial PDU session to be stablished'                                                       'O|text'
    'UE_SESSION_SST'          'configure' 'UE SST of of initial PDU session to be stablished'                                                   'O|text'
    'UE_SUPI'                 'configure' 'IMSI number of the UE. IMSI = [MCC|MNC|MSISDN] (In total 15 digits)'                                 'O|text'
)



GNB_MCC="${GNB_MCC:-999}"
GNB_MNC="${GNB_MNC:-70}"
GNB_SLICES_SD="${GNB_SLICES_SD:-1}"
GNB_SLICES_SST="${GNB_SLICES_SST:-1}"
GNB_TAC="${GNB_TAC:-1}"
UE_CONFIGURED_NSSAI_SST="${UE_CONFIGURED_NSSAI_SST:-1}"
UE_DEFAULT_NSSAI_SD="${UE_DEFAULT_NSSAI_SD:-1}"
UE_DEFAULT_NSSAI_SST="${UE_DEFAULT_NSSAI_SST:-1}"
UE_GNBSEARCHLIST="${UE_GNBSEARCHLIST:-127.0.0.1}"
UE_KEY="${UE_KEY:-465B5CE8B199B49FAA5F0A2EE238A6BC}"
UE_MCC="${UE_MCC:-999}"
UE_MNC="${UE_MNC:-70}"
UE_OP="${UE_KEY:-E8ED289DEBA952E4283B54E88E6183CA}"
UE_SESSION_APN="${UE_SESSION_APN:-internet}"
UE_SESSION_SST="${UE_SESSION_SST:-1}"
UE_SUPI="${UE_SUPI:-imsi-999700000000001}"


# ------------------------------------------------------------------------------
# Global variables
# ------------------------------------------------------------------------------

DEP_PKGS= "libsctp-dev lksctp-tools iproute2 wget moreutils"



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
    install_pkg_deps DEP_PKGS

    # yaml query
    install_yq

    # services
    define_services

    # service metadata
    create_one_service_metadata

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

    msg info "Install required packages for TNLCM"
    if ! apt-get install -y ${!1} ; then
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

postinstall_cleanup()
{
    msg info "Delete cache and stored packages"
    apt-get autoclean
    apt-get autoremove
    rm -rf /var/lib/apt/lists/*
}

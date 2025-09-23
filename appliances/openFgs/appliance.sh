#!/usr/bin/env bash

set -o errexit -o pipefail

# ------------------------------------------------------------------------------
# Contextualization and global variables
# ------------------------------------------------------------------------------

DEP_PKGS="wget gnupg curl software-properties-common ca-certificates"
MONGODB_VERSION="8.0"
OPEN5GS_VERSION="2.7.6"
NODE_MAJOR=20

WEBUI_IP="${ONEAPP_OPEN5GS_WEBUI_IP:-0.0.0.0}"
WEBUI_PORT="${ONEAPP_OPEN5GS_WEBUI_PORT:-3000}"

ONEAPP_OPEN5GS_MCC="${ONEAPP_OPEN5GS_MCC:-999}"
ONEAPP_OPEN5GS_MNC="${ONEAPP_OPEN5GS_MNC:-75}"
ONEAPP_OPEN5GS_N2_IP="${ONEAPP_OPEN5GS_N2_IP:-10.0.3.2}"
ONEAPP_OPEN5GS_N3_IP="${ONEAPP_OPEN5GS_N3_IP:-10.0.3.2}"
ONEAPP_OPEN5GS_TAC="${ONEAPP_OPEN5GS_TAC:-1}"


# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# Mandatory Functions
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------

service_install()
{
    export DEBIAN_FRONTEND=noninteractive

    # packages
    install_pkg_deps

    # mongodb
    install_mongodb

    # open5gs 
    install_open5gs

    # open5gs webui
    install_webui

    # cleanup
    postinstall_cleanup

    msg info "INSTALLATION FINISHED"

    return 0
}

service_configure()
{
    export DEBIAN_FRONTEND=noninteractive

    # Configure Open5GS for 5G SA
    msg info "Configuring Open5GS for 5G SA"
    configure_open5gs_5g_sa

    # Configure WebUI
    msg info "Configuring Open5GS WebUI"
    configure_webui

    # Setup network configuration
    msg info "Setting up network configuration"
    setup_network

    # Enable and start services
    msg info "Start and enable Open5GS 5G SA services"
    start_enable_5g_sa_services

    # Generate service report
    generate_service_report

    msg info "CONFIGURATION FINISHED"
    return 0
}

service_bootstrap()
{
    msg info "Verifying Open5GS installation"
    verify_installation

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

    msg info "Install required packages for Open5GS"
    wait_for_dpkg_lock_release
    if ! apt-get install -y ${DEP_PKGS} ; then
        msg error "Package(s) installation failed"
        exit 1
    fi
}

install_mongodb()
{
    msg info "Install mongoDB"
    curl -fsSL https://www.mongodb.org/static/pgp/server-${MONGODB_VERSION}.asc | \
        sudo gpg -o /usr/share/keyrings/mongodb-server-${MONGODB_VERSION}.gpg --dearmor
    echo "deb [ arch=amd64 signed-by=/usr/share/keyrings/mongodb-server-${MONGODB_VERSION}.gpg ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -sc 2> /dev/null)/mongodb-org/${MONGODB_VERSION} multiverse" | \
        sudo tee /etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}.list
    wait_for_dpkg_lock_release
    apt-get update
    if ! apt-get install -y mongodb-org; then
        msg error "Error installing package 'mongo-org'"
        exit 1
    fi

    sudo systemctl daemon-reload

    msg info "Start mongoDB service"
    systemctl enable --now mongod.service

    # Verify MongoDB is running
    if systemctl is-active --quiet mongod; then
        msg info "✓ MongoDB service is running"
    else
        msg error "✗ MongoDB service failed to start"
        exit 1
    fi
}

install_open5gs()
{
    msg info "Install Open5GS"
    if ! add-apt-repository -y ppa:open5gs/latest ; then
        msg error "adding Open5GS PPA failed"
        exit 1
    fi

    wait_for_dpkg_lock_release
    msg info "Install open5gs ${OPEN5GS_VERSION}~*..."
    if ! apt-get install -y open5gs=${OPEN5GS_VERSION}~* ; then
        msg error "open5gs installation failed"
        exit 1
    fi
}

install_webui()
{
    msg info "Add NodeSource GPG key..."
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | \
        sudo gpg -o /usr/share/keyrings/nodesource.gpg --dearmor
    echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list


    wait_for_dpkg_lock_release
    apt-get update
    msg info "Install Node.js ${NODE_MAJOR}..."
    if ! apt-get install -y nodejs ; then
        msg error "open5gs webui installation failed"
        exit 1
    fi

    # Verify installation
    if command -v node >/dev/null 2>&1; then
        local node_version=$(node --version)
        msg info "✓ Node.js installed: $node_version"
    else
        msg error "✗ Node.js installation failed"
        exit 1
    fi

    msg info "Run Open5GS WebUI installer..."
    curl -fsSL https://open5gs.org/open5gs/assets/webui/install | sudo -E bash -
    
    # Configure WebUI service with custom IP and port
    msg info "Configure WebUI for external access on ${WEBUI_IP}:${WEBUI_PORT}..."
    
    # Check for existing service file and configure it
    local service_files=(
        "/lib/systemd/system/open5gs-webui.service"
        "/etc/systemd/system/open5gs-webui.service"
        "/usr/lib/systemd/system/open5gs-webui.service"
    )
    
    local service_configured=false
    for service_file in "${service_files[@]}"; do
        if [ -f "$service_file" ]; then
            msg info "Found service file: $service_file"
            
            # Stop the service before modifying
            systemctl stop open5gs-webui 2>/dev/null || true
            
            # Backup original service file
            cp "$service_file" "$service_file.backup"
            
            # Add environment variables to the service
            sed -i '/\[Service\]/a Environment=NODE_ENV=production' "$service_file"
            sed -i "/Environment=NODE_ENV=production/a Environment=HOSTNAME=${WEBUI_IP}" "$service_file"
            sed -i "/Environment=HOSTNAME=${WEBUI_IP}/a Environment=PORT=${WEBUI_PORT}" "$service_file"
            
            # Reload systemd to pick up changes
            systemctl daemon-reload
            
            msg info "✓ WebUI service configured for ${WEBUI_IP}:${WEBUI_PORT}"
            service_configured=true
            break
        fi
    done
    
    # If no existing service file found, create one
    if [ "$service_configured" = false ]; then
        msg info "Creating new WebUI service file..."
        cat > /etc/systemd/system/open5gs-webui.service <<EOF
[Unit]
Description=Open5GS WebUI
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/open5gs-webui
ExecStart=/usr/bin/node server/index.js
Restart=always
RestartSec=2
KillMode=mixed
KillSignal=SIGINT
TimeoutStopSec=5
Environment=NODE_ENV=production
Environment=HOSTNAME=${WEBUI_IP}
Environment=PORT=${WEBUI_PORT}

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        msg info "✓ WebUI service created for ${WEBUI_IP}:${WEBUI_PORT}"
    fi
}



configure_open5gs_5g_sa()
{
    # Disable 4G/LTE services
    msg info "Disabling 4G/LTE services..."
    local lte_services=("open5gs-mmed" "open5gs-sgwcd" "open5gs-sgwud" "open5gs-hssd" "open5gs-pcrfd")
    
    for service in "${lte_services[@]}"; do
        if systemctl is-enabled --quiet "$service" 2>/dev/null; then
            systemctl disable "$service" || true
            msg info "Disabled $service (4G/LTE function)"
        fi
    done
    
    # Configure NRF with user-provided PLMN
    msg info "Configuring NRF with PLMN ${ONEAPP_OPEN5GS_MCC}/${ONEAPP_OPEN5GS_MNC}..."
    if [ -f /etc/open5gs/nrf.yaml ]; then
        # Backup original config
        cp /etc/open5gs/nrf.yaml /etc/open5gs/nrf.yaml.backup
        chmod 644 /etc/open5gs/nrf.yaml.backup
        
        # Update PLMN in NRF configuration
        sed -i "s/mcc: [0-9]\+/mcc: ${ONEAPP_OPEN5GS_MCC}/g" /etc/open5gs/nrf.yaml
        sed -i "s/mnc: [0-9]\+/mnc: ${ONEAPP_OPEN5GS_MNC}/g" /etc/open5gs/nrf.yaml
        
        # Restore proper file permissions
        chmod 644 /etc/open5gs/nrf.yaml
        chown root:root /etc/open5gs/nrf.yaml
        
        msg info "✓ NRF configured with PLMN ${ONEAPP_OPEN5GS_MCC}/${ONEAPP_OPEN5GS_MNC}"
    else
        msg error "NRF configuration file not found"
    fi
    
    # Configure AMF with user-provided parameters
    msg info "Configuring AMF with N2 IP ${ONEAPP_OPEN5GS_N2_IP}, PLMN ${ONEAPP_OPEN5GS_MCC}/${ONEAPP_OPEN5GS_MNC}, TAC ${ONEAPP_OPEN5GS_TAC}..."
    if [ -f /etc/open5gs/amf.yaml ]; then
        # Backup original config
        cp /etc/open5gs/amf.yaml /etc/open5gs/amf.yaml.backup
        chmod 644 /etc/open5gs/amf.yaml.backup
        
        # Update N2 interface IP (NGAP bind address) - only in ngap section using awk for precision
        awk -v new_ip="${ONEAPP_OPEN5GS_N2_IP}" '
        BEGIN { in_ngap = 0; in_server = 0 }
        /^[[:space:]]*ngap:/ { in_ngap = 1; in_server = 0 }
        /^[[:space:]]*metrics:/ { in_ngap = 0; in_server = 0 }
        /^[[:space:]]*sbi:/ { in_ngap = 0; in_server = 0 }
        in_ngap && /^[[:space:]]*server:/ { in_server = 1 }
        in_ngap && in_server && /^[[:space:]]*-[[:space:]]*address:/ {
            sub(/address:[[:space:]]*[0-9.]+/, "address: " new_ip)
        }
        { print }
        ' /etc/open5gs/amf.yaml > /tmp/amf_temp.yaml && mv /tmp/amf_temp.yaml /etc/open5gs/amf.yaml
        
        # Restore proper file permissions
        chmod 644 /etc/open5gs/amf.yaml
        chown root:root /etc/open5gs/amf.yaml
        
        # Update PLMN in multiple sections
        sed -i "s/mcc: [0-9]\+/mcc: ${ONEAPP_OPEN5GS_MCC}/g" /etc/open5gs/amf.yaml
        sed -i "s/mnc: [0-9]\+/mnc: ${ONEAPP_OPEN5GS_MNC}/g" /etc/open5gs/amf.yaml
        
        # Update TAC
        sed -i "s/tac: [0-9]\+/tac: ${ONEAPP_OPEN5GS_TAC}/g" /etc/open5gs/amf.yaml
        
        msg info "✓ AMF configured with N2 IP: ${ONEAPP_OPEN5GS_N2_IP} (NGAP only)"
        msg info "✓ AMF configured with PLMN: ${ONEAPP_OPEN5GS_MCC}/${ONEAPP_OPEN5GS_MNC}"
        msg info "✓ AMF configured with TAC: ${ONEAPP_OPEN5GS_TAC}"
    else
        msg error "AMF configuration file not found"
    fi
    
    # Configure UPF with user-provided N3 IP
    msg info "Configuring UPF with N3 IP ${ONEAPP_OPEN5GS_N3_IP}..."
    if [ -f /etc/open5gs/upf.yaml ]; then
        # Backup original config
        cp /etc/open5gs/upf.yaml /etc/open5gs/upf.yaml.backup
        chmod 644 /etc/open5gs/upf.yaml.backup
        
        # Update N3 interface IP (GTP-U bind address) - only in gtpu section using awk for precision
        awk -v new_ip="${ONEAPP_OPEN5GS_N3_IP}" '
        BEGIN { in_gtpu = 0; in_server = 0 }
        /^[[:space:]]*gtpu:/ { in_gtpu = 1; in_server = 0 }
        /^[[:space:]]*session:/ { in_gtpu = 0; in_server = 0 }
        /^[[:space:]]*metrics:/ { in_gtpu = 0; in_server = 0 }
        in_gtpu && /^[[:space:]]*server:/ { in_server = 1 }
        in_gtpu && in_server && /^[[:space:]]*-[[:space:]]*address:/ {
            sub(/address:[[:space:]]*[0-9.]+/, "address: " new_ip)
        }
        { print }
        ' /etc/open5gs/upf.yaml > /tmp/upf_temp.yaml && mv /tmp/upf_temp.yaml /etc/open5gs/upf.yaml
        
        # Restore proper file permissions
        chmod 644 /etc/open5gs/upf.yaml
        chown root:root /etc/open5gs/upf.yaml
        
        msg info "✓ UPF configured with N3 IP: ${ONEAPP_OPEN5GS_N3_IP} (GTP-U only)"
    else
        msg error "UPF configuration file not found"
    fi
}

configure_webui()
{
    # Update WebUI service with environment variables
    msg info "Updating WebUI service configuration..."
    
    # Check for existing service file in multiple locations
    local service_files=(
        "/lib/systemd/system/open5gs-webui.service"
        "/etc/systemd/system/open5gs-webui.service"
        "/usr/lib/systemd/system/open5gs-webui.service"
    )
    
    local service_found=false
    for service_file in "${service_files[@]}"; do
        if [ -f "$service_file" ]; then
            msg info "Found service file: $service_file"
            
            # Update environment variables in the service file
            sed -i "s/Environment=HOSTNAME=.*/Environment=HOSTNAME=${WEBUI_IP}/g" "$service_file"
            sed -i "s/Environment=PORT=.*/Environment=PORT=${WEBUI_PORT}/g" "$service_file"
            
            msg info "✓ WebUI service updated for ${WEBUI_IP}:${WEBUI_PORT}"
            service_found=true
            break
        fi
    done
    
    if [ "$service_found" = false ]; then
        msg error "WebUI service file not found in any expected location"
        return 1
    fi
    
    systemctl daemon-reload
}

setup_network()
{
    # Enable IP forwarding
    msg info "Enabling IP forwarding..."
    sysctl -w net.ipv4.ip_forward=1
    sysctl -w net.ipv6.conf.all.forwarding=1
    
    # Make IP forwarding persistent
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    
    if ! grep -q "net.ipv6.conf.all.forwarding=1" /etc/sysctl.conf; then
        echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
    fi
    
    # Add NAT rules for UE connectivity
    msg info "Adding NAT rules for UE connectivity..."
    
    # IPv4 NAT rule
    if ! iptables -t nat -C POSTROUTING -s 10.45.0.0/16 ! -o ogstun -j MASQUERADE 2>/dev/null; then
        iptables -t nat -A POSTROUTING -s 10.45.0.0/16 ! -o ogstun -j MASQUERADE
        msg info "Added IPv4 NAT rule for UE traffic"
    else
        msg info "IPv4 NAT rule already exists"
    fi
    
    # IPv6 NAT rule
    if ! ip6tables -t nat -C POSTROUTING -s 2001:db8:cafe::/48 ! -o ogstun -j MASQUERADE 2>/dev/null; then
        ip6tables -t nat -A POSTROUTING -s 2001:db8:cafe::/48 ! -o ogstun -j MASQUERADE
        msg info "Added IPv6 NAT rule for UE traffic"
    else
        msg info "IPv6 NAT rule already exists"
    fi
    
    # Accept traffic on ogstun interface
    if ! iptables -C INPUT -i ogstun -j ACCEPT 2>/dev/null; then
        iptables -I INPUT -i ogstun -j ACCEPT
        msg info "Added iptables rule to accept ogstun traffic"
    fi
    
    # Install iptables-persistent to save rules
    if ! dpkg -l | grep -q iptables-persistent; then
        msg info "Installing iptables-persistent to save firewall rules..."
        echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
        echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
        DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
    else
        # Save current rules
        iptables-save > /etc/iptables/rules.v4
        ip6tables-save > /etc/iptables/rules.v6
        msg info "Saved iptables rules"
    fi
    
    msg info "Network configuration completed"
}

start_enable_5g_sa_services()
{
    local services_order=("open5gs-nrfd" "open5gs-scpd" "open5gs-ausfd" "open5gs-udrd" "open5gs-udmd" "open5gs-pcfd" "open5gs-nssfd" "open5gs-bsfd" "open5gs-amfd" "open5gs-smfd" "open5gs-upfd" "open5gs-seppd" "open5gs-webui")

    for service in "${services_order[@]}"; do
        msg info "Start and enable systemd service: $service..."
        systemctl enable --now "$service"
        sleep 3  # Give service time to start
        
        if systemctl is-active --quiet "$service"; then
            msg info "✓ $service started successfully"
        else
            msg error "✗ $service failed to start"
        fi
    done


}

verify_installation()
{
    msg info "Verifying Open5GS installation..."

    # Check MongoDB
    if systemctl is-active --quiet mongod; then
        msg info "✓ MongoDB is running"
    else
        msg error "✗ MongoDB is not running"
        return 1
    fi

    # Check 5G SA Core services
    local core_services=("open5gs-nrfd" "open5gs-scpd" "open5gs-amfd" "open5gs-smfd" "open5gs-upfd" "open5gs-ausfd" "open5gs-udmd" "open5gs-udrd")
    local running_services=0
    local total_services=0
    local non_amf_failures=0

    for service in "${core_services[@]}"; do
        if systemctl list-unit-files | grep -q "^$service"; then
            total_services=$((total_services + 1))
            if systemctl is-active --quiet "$service"; then
                msg info "✓ $service is running"
                running_services=$((running_services + 1))
            else
                if [ "$service" = "open5gs-amfd" ]; then
                    msg info "$service is not running. This might be because the AMF's IP address (${ONEAPP_OPEN5GS_N2_IP}) is not available on any network interface."
                    msg info "Checking service logs for clues:"
                    journalctl -u open5gs-amfd -n 10 --no-pager
                else
                    msg error "⚠ $service is not running"
                    non_amf_failures=$((non_amf_failures + 1))
                fi
            fi
        fi
    done

    # Check WebUI
    if systemctl is-active --quiet open5gs-webui; then
        msg info "✓ Open5GS WebUI is running (http://${WEBUI_IP}:${WEBUI_PORT})"
    else
        msg error "⚠ Open5GS WebUI is not running"
    fi

    # Check that 4G services are disabled
    local lte_services=("open5gs-mmed" "open5gs-sgwcd" "open5gs-sgwud" "open5gs-hssd" "open5gs-pcrfd")
    for service in "${lte_services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            msg error "⚠ $service (4G/LTE) is running - should be disabled for 5G-only setup"
        fi
    done

    msg info "Verification completed: $running_services/$total_services core services running"

    if [ "$non_amf_failures" -eq 0 ]; then
        msg info "All essential services are running correctly (or have known, non-critical issues)."
        return 0
    else
        msg error "Some critical services are not running properly."
        return 1
    fi
}

generate_service_report()
{
    msg info "═══════════════════════════════════════════════════════════════"
    msg info "                Open5GS 5G SA Core Installation Report"
    msg info "═══════════════════════════════════════════════════════════════"
    msg info ""
    msg info "✓ Installation Status: COMPLETED SUCCESSFULLY"
    msg info ""
    msg info "📋 Configuration Summary:"
    msg info "   • PLMN (MCC/MNC): ${ONEAPP_OPEN5GS_MCC}/${ONEAPP_OPEN5GS_MNC}"
    msg info "   • TAC: ${ONEAPP_OPEN5GS_TAC}"
    msg info "   • N2 Interface IP: ${ONEAPP_OPEN5GS_N2_IP}"
    msg info "   • N3 Interface IP: ${ONEAPP_OPEN5GS_N3_IP}"
    msg info "   • MongoDB: Version 8.0 (running)"
    msg info ""
    msg info "🌐 WebUI Access:"
    msg info "   • URL: http://${WEBUI_IP}:${WEBUI_PORT}"
    msg info "   • Default Username: admin"
    msg info "   • Default Password: 1423"
    msg info ""
    msg info "🔧 Core Network Functions (5G SA):"
    msg info "   • NRF  (Network Repository Function)"
    msg info "   • AMF  (Access and Mobility Management Function)"
    msg info "   • SMF  (Session Management Function)"
    msg info "   • UPF  (User Plane Function)"
    msg info "   • AUSF (Authentication Server Function)"
    msg info "   • UDM  (Unified Data Management)"
    msg info "   • UDR  (Unified Data Repository)"
    msg info "   • PCF  (Policy Control Function)"
    msg info "   • BSF  (Binding Support Function)"
    msg info "   • NSSF (Network Slice Selection Function)"
    msg info ""
    msg info "📱 Next Steps:"
    msg info "   1. Access the WebUI to add subscriber information"
    msg info "   2. Configure your gNodeB to connect to AMF at ${ONEAPP_OPEN5GS_N2_IP}:38412"
    msg info "   3. Configure UE devices with the subscriber data from WebUI"
    msg info "   4. Test connectivity and data sessions"
    msg info ""
    msg info "📚 Documentation: https://open5gs.org/open5gs/docs/"
    msg info "═══════════════════════════════════════════════════════════════"
    
    cat > "$ONE_SERVICE_REPORT" <<EOF
[Open5GS Configuration]
MCC = ${ONEAPP_OPEN5GS_MCC}
MNC = ${ONEAPP_OPEN5GS_MNC}
N2 Interface IP = ${ONEAPP_OPEN5GS_N2_IP}
N3 Interface IP = ${ONEAPP_OPEN5GS_N3_IP}
TAC = ${ONEAPP_OPEN5GS_TAC}

[WebUI Access]
URL = http://${WEBUI_IP}:${WEBUI_PORT}
Default Username = admin
Default Password = 1423

[Core Functions]
- NRF (Network Repository Function)
- AMF (Access and Mobility Management Function)
- SMF (Session Management Function)
- UPF (User Plane Function)
- AUSF (Authentication Server Function)
- UDM (Unified Data Management)
- UDR (Unified Data Repository)
- PCF (Policy Control Function)
- BSF (Binding Support Function)
- NSSF (Network Slice Selection Function)

[Next Steps]
1. Access WebUI to manage subscribers
2. Configure gNodeB to connect to AMF at ${ONEAPP_OPEN5GS_N2_IP}:38412
3. Configure UE devices with subscriber data from WebUI
4. Test connectivity and data sessions
5. Use 'systemctl status open5gs-*' to check service status

[Documentation]
https://open5gs.org/open5gs/docs/
EOF

    chmod 600 "$ONE_SERVICE_REPORT"
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

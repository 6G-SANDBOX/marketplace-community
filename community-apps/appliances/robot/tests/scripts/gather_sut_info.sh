#!/bin/bash

# ----------------------------------------
# Script to gather SUT system information
# Generates a JSON report with various system metrics.
# Arguments:
#   $1 - Output JSON file
#   $2 - iperf server address (hostname or IP)
#   $3 - Public endpoint for reachability test
# ----------------------------------------

# Validate arguments
if [ $# -ne 3 ]; then
    echo "Usage: $0 <output_file.json> <iperf_server> <public_endpoint>"
    echo "Example: $0 sut_info.json iperf.opennebula.local http://example.com"
    exit 1
fi

OUTPUT_FILE="$1"
IPERF_SERVER="$2"
PUBLIC_ENDPOINT="$3"

# Function to get the hostname
get_hostname() {
    hostname
}

# Function to get interfaces and IP addresses
get_ip_info() {
    ip -o -4 addr show | awk '{print $2, $4}' | tr '\n' ';'
}

# Function to get basic OS details
get_os_details() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$PRETTY_NAME"
    else
        uname -a
    fi
}

# Function to get GPU information (if any)
get_gpu_info() {
    if command -v lspci >/dev/null 2>&1; then
        GPU_INFO=$(lspci | grep -i 'vga\|3d\|nvidia' || echo "No GPU detected")
    else
        GPU_INFO="lspci not available to detect GPU"
    fi

    if command -v nvidia-smi >/dev/null 2>&1; then
        VRAM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n 1 || echo "Unknown VRAM")
        GPU_INFO="$GPU_INFO, VRAM=${VRAM}MB"
    fi

    echo "$GPU_INFO"
}

# Function to determine the default interface for iperf
get_iperf_interface() {
    DEF_IF=$(ip route get 8.8.8.8 | awk '{print $5; exit}' || echo "Unknown")
    echo "$DEF_IF"
}

# Function to validate DNS resolution and external reachability
validate_dns_reachability() {
    PING_RESULT=$(ping -c 2 8.8.8.8 >/dev/null 2>&1 && echo "OK" || echo "FAIL")
    CURL_RESULT=$(curl -s --max-time 5 "$PUBLIC_ENDPOINT" >/dev/null && echo "OK" || echo "FAIL")
    echo "Ping: $PING_RESULT, Curl: $CURL_RESULT"
}

# Function to validate connectivity to the iperf server
validate_iperf_reachability() {
    ping -c 2 "$IPERF_SERVER" >/dev/null 2>&1 && echo "OK" || echo "FAIL"
}

# Function to get mounted disks and filesystem information
get_disk_info() {
    df -h --output=source,fstype,size,used,avail,target | tail -n +2 | tr '\n' ';'
}

# ---------------- DATA COLLECTION ----------------

HOSTNAME=$(get_hostname)
IP_INFO=$(get_ip_info)
OS_DETAILS=$(get_os_details)
GPU_INFO=$(get_gpu_info)
IPERF_IFACE=$(get_iperf_interface)
DNS_REACHABILITY=$(validate_dns_reachability)
IPERF_REACHABILITY=$(validate_iperf_reachability)
DISK_INFO=$(get_disk_info)

# ---------------- JSON CREATION ----------------

cat <<EOF > "$OUTPUT_FILE"
{
    "hostname": "$HOSTNAME",
    "ip_addresses_and_interfaces": "$IP_INFO",
    "os_details": "$OS_DETAILS",
    "gpu_info": "$GPU_INFO",
    "iperf_interface": "$IPERF_IFACE",
    "dns_and_reachability": "$DNS_REACHABILITY",
    "iperf_server_reachability": "$IPERF_REACHABILITY",
    "mounted_disks": "$DISK_INFO"
}
EOF

echo "Information successfully collected and saved to $OUTPUT_FILE"

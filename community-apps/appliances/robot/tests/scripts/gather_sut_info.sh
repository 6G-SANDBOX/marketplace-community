#!/bin/bash

# ----------------------------------------
# Script to gather SUT system information
# Generates a structured JSON report.
# Usage:
#   $0 <output_file.json> <iperf_server> <public_endpoint>
# ----------------------------------------

if [ $# -ne 3 ]; then
    echo "Usage: $0 <output_file.json> <iperf_server> <public_endpoint>"
    exit 1
fi

OUTPUT_FILE="$1"
IPERF_SERVER="$2"
PUBLIC_ENDPOINT="$3"

# Get current timestamp in ISO 8601
get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

get_hostname() {
    hostname
}

get_ip_info() {
    ip -o -4 addr show | awk '{print "{\"interface\": \"" $2 "\", \"ip\": \"" $4 "\"},"}'
}

get_os_details() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$PRETTY_NAME"
    else
        uname -a
    fi
}

# Get CPU info
get_cpu_info() {
    MODEL=$(lscpu | grep "Model name" | awk -F: '{print $2}' | xargs)
    CORES=$(lscpu | grep "^CPU(s):" | awk '{print $2}')
    SOCKETS=$(lscpu | grep "Socket(s):" | awk '{print $2}')
    THREADS_PER_CORE=$(lscpu | grep "Thread(s) per core:" | awk '{print $4}')
    PHYSICAL_CORES=$(( SOCKETS * (CORES / THREADS_PER_CORE) ))

    # Per-core usage with mpstat
    if command -v mpstat >/dev/null 2>&1; then
        CORE_USAGES=$(mpstat -P ALL 1 1 | awk '/^[0-9]/ && $2 ~ /^[0-9]+$/ {core=$2; usage=100 - $12; printf("{\"core\": %s, \"usage_percent\": %.2f},", core, usage)}')
        CORE_USAGES=$(echo "$CORE_USAGES" | sed 's/,$//')  # Remove trailing comma
        echo "{\"model\": \"${MODEL}\", \"physical_cores\": ${PHYSICAL_CORES}, \"logical_cores\": ${CORES}, \"per_core_usage\": [${CORE_USAGES}]}"
    else
        echo "{\"model\": \"${MODEL}\", \"physical_cores\": ${PHYSICAL_CORES}, \"logical_cores\": ${CORES}, \"per_core_usage\": []}"
    fi
}

get_gpu_info() {
    local gpu_list="[]"

    if command -v nvidia-smi >/dev/null 2>&1; then
        # Obtener nombres y VRAM
        mapfile -t gpu_names < <(nvidia-smi --query-gpu=name --format=csv,noheader)
        mapfile -t gpu_vram  < <(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits)

        if [ ${#gpu_names[@]} -gt 0 ]; then
            gpu_list="["
            for i in "${!gpu_names[@]}"; do
                name="${gpu_names[$i]}"
                vram="${gpu_vram[$i]}"
                gpu_list+="{\"description\": \"${name}\", \"vram_mb\": ${vram}},"
            done
            gpu_list="${gpu_list%,}]"  # Quitar la última coma y cerrar array
        fi
    fi

    # Si no hay NVIDIA o nvidia-smi no está
    if [ "$gpu_list" = "[]" ]; then
        gpu_list="[ {\"description\": \"No accelerator present\", \"vram_mb\": null} ]"
    fi

    echo "${gpu_list}"
}

# Get RAM info
get_ram_info() {
    read -r TOTAL USED FREE <<< $(free -m | awk '/^Mem:/ {print $2, $3, $4}')
    echo "{\"total_mb\": ${TOTAL}, \"used_mb\": ${USED}, \"free_mb\": ${FREE}}"
}

get_iperf_interface() {
    ip route get $IPERF_SERVER | awk '{print $5; exit}' || echo "Unknown"
}

validate_dns_reachability() {
    PING=$(ping -c 2 8.8.8.8 >/dev/null 2>&1 && echo "OK" || echo "FAIL")
    # CURL=$(curl -s --max-time 5 "$PUBLIC_ENDPOINT" >/dev/null && echo "OK" || echo "FAIL")
    # echo "{\"ping_8_8_8_8\": \"$PING\", \"curl_public_endpoint\": \"$CURL\"}"
    echo "{\"ping_8_8_8_8\": \"$PING\"}"
}

validate_iperf_reachability() {
    ping -c 2 "$IPERF_SERVER" >/dev/null 2>&1 && echo "\"OK\"" || echo "\"FAIL\""
}

get_disk_info() {
    df -h --output=source,fstype,size,used,avail,target | tail -n +2 | \
    awk '{print "{\"device\": \"" $1 "\", \"type\": \"" $2 "\", \"size\": \"" $3 "\", \"used\": \"" $4 "\", \"available\": \"" $5 "\", \"mountpoint\": \"" $6 "\"},"}'
}

# ---------------- DATA COLLECTION ----------------

TIMESTAMP=$(get_timestamp)
HOSTNAME=$(get_hostname)
IP_INFO=$(get_ip_info | sed '$ s/,$//')  # Remove last comma
OS_DETAILS=$(get_os_details)
GPU_INFO=$(get_gpu_info)
CPU_INFO=$(get_cpu_info)
RAM_MB=$(get_ram_info)
IPERF_IFACE=$(get_iperf_interface)
DNS_REACHABILITY=$(validate_dns_reachability)
IPERF_REACHABILITY=$(validate_iperf_reachability)
DISK_INFO=$(get_disk_info | sed '$ s/,$//')  # Remove last comma

# ---------------- JSON CREATION ----------------

cat <<EOF > "$OUTPUT_FILE"
{
    "timestamp": "$TIMESTAMP",
    "hostname": "$HOSTNAME",
    "os_details": "$OS_DETAILS",
    "cpu_info": $CPU_INFO,
    "ram_info": $RAM_MB,
    "gpu_info": $GPU_INFO,
    "ip_addresses_and_interfaces": [
        $IP_INFO
    ],
    "iperf_interface": "$IPERF_IFACE",
    "dns_and_reachability": $DNS_REACHABILITY,
    "iperf_server_reachability": $IPERF_REACHABILITY,
    "mounted_disks": [
        $DISK_INFO
    ]
}
EOF

echo "Structured JSON saved to $OUTPUT_FILE"

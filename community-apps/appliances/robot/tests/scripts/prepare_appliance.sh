#!/bin/bash

# ----------------------------------------
# Script to gather SUT system information
# Generates a structured JSON report.
# Usage:
#   $0 <output_file.json> <iperf_server> <public_endpoint>
# ----------------------------------------

if [ $# -ne 1 ]; then
    echo "Usage: $0 <output_file.json>"
    exit 1
fi

OUTPUT_FILE="$1"

# Obtener el nombre del archivo
FILENAME=$(basename "$OUTPUT_FILE")
FILENAME_NOEXT="${FILENAME%.*}"

# Obtener el path del directorio
FILE_PATH=$(dirname "$OUTPUT_FILE")

# Set non-interactive mode
export DEBIAN_FRONTEND=noninteractive

# Log files
LOG_FILE="$FILE_PATH/$FILENAME_NOEXT.log"
JSON_FILE="$FILE_PATH/$FILENAME"

# Create log file if it doesn't exist
if [ ! -f "$JSON_FILE" ]; then
    echo "{}" > "$JSON_FILE"
fi

# Create log and JSON files
echo "FILENAME: $FILENAME"
echo "FILENAME_NOEXT: $FILENAME_NOEXT"
echo "FILE_PATH: $FILE_PATH"
echo "OUTPUT_FILE: $OUTPUT_FILE"
echo "LOG_FILE: $LOG_FILE"
echo "JSON_FILE: $JSON_FILE"


# Function to install a package and check for errors
install_package() {
    PKG_NAME=$1
    CMD_CHECK=$2
    INSTALL_CMD=$3

    if ! command -v $CMD_CHECK &>/dev/null; then
        echo "🔹 Installing $PKG_NAME..."
        if eval $INSTALL_CMD; then
            echo "✅ $PKG_NAME installed successfully."
            jq --arg key "$PKG_NAME" --arg value "Installed" '.[$key] = $value' "$JSON_FILE" > temp.json && mv temp.json "$JSON_FILE"
        else
            echo "❌ ERROR: Failed to install $PKG_NAME." | tee -a $LOG_FILE
            jq --arg key "$PKG_NAME" --arg value "Failed" '.[$key] = $value' "$JSON_FILE" > temp.json && mv temp.json "$JSON_FILE"
        fi
    else
        echo "✅ $PKG_NAME is already installed."
        jq --arg key "$PKG_NAME" --arg value "Already Installed" '.[$key] = $value' "$JSON_FILE" > temp.json && mv temp.json "$JSON_FILE"
    fi
}

# System update and install essential tools
echo "🔹 Updating system and installing necessary tools..."
apt update -y && apt upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
apt install -y --no-install-recommends curl wget software-properties-common pciutils jq python3 python3-pip python3-venv

# Install benchmarking tools
install_package "Sysstat" "iostat" "apt install -y --no-install-recommends sysstat"
install_package "Sysbench" "sysbench" "apt install -y --no-install-recommends sysbench"
install_package "Stress-ng" "stress-ng" "apt install -y --no-install-recommends stress-ng"
install_package "FIO" "fio" "apt install -y --no-install-recommends fio"
install_package "Iperf3" "iperf3" "apt install -y --no-install-recommends iperf3"
install_package "Memtester" "memtester" "apt install -y --no-install-recommends memtester"
install_package "Hdparm" "hdparm" "apt install -y --no-install-recommends hdparm"

# Install NVIDIA drivers and CUDA (if a GPU is detected)
if lspci | grep -i nvidia; then
    echo "🔹 NVIDIA GPU detected, installing CUDA and TensorFlow..."
    add-apt-repository -y ppa:graphics-drivers/ppa
    apt update
    install_package "NVIDIA Driver" "nvidia-smi" "apt install -y --no-install-recommends nvidia-driver-535"
        
    # Set up TensorFlow GPU
    # install_package "Python Virtual Env" "virtualenv" "pip install virtualenv"
    python3 -m venv tf_gpu_env
    source tf_gpu_env/bin/activate
    pip install --upgrade pip
    pip install tensorflow
fi

echo "✅ Installation complete. Exiting without running benchmarks."
exit 0


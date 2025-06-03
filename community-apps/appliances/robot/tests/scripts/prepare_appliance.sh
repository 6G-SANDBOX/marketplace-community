#!/bin/bash

# ----------------------------------------
# Script to gather SUT system information
# Generates a structured JSON report.
# Usage:
#   $0 <output_file.json>
# ----------------------------------------

# Help message
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --json <filename>       Specify the JSON output file."
    echo "  --help                  Show this help message and exit."
    echo ""
    exit 0
}

OUTPUT_FILE="prepare_appliance_$(date +%Y%m%d_%H%M%S).json"

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)
            if [[ -n "$2" && "$2" != --* ]]; then
                OUTPUT_FILE="$2"
                shift
            else
                echo "❌ ERROR: --json requires a filename argument."
                show_help
            fi
            ;;
        *)
            echo "❌ Unknown option: $1"
            show_help
            ;;
    esac
    shift
done

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
    echo '{"preparation": {}}' > "$JSON_FILE"
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
            jq --arg key "$PKG_NAME" --arg value "Installed" '.preparation.apt[$key] = $value' "$JSON_FILE" > temp.json && mv temp.json "$JSON_FILE"
        else
            echo "❌ ERROR: Failed to install $PKG_NAME." | tee -a $LOG_FILE
            jq --arg key "$PKG_NAME" --arg value "Failed" '.preparation.apt[$key] = $value' "$JSON_FILE" > temp.json && mv temp.json "$JSON_FILE"
        fi
    else
        echo "✅ $PKG_NAME is already installed."
        jq --arg key "$PKG_NAME" --arg value "Already Installed" '.preparation.apt[$key] = $value' "$JSON_FILE" > temp.json && mv temp.json "$JSON_FILE"
    fi
}

# System update and install essential tools
echo "🔹 Updating system and installing necessary tools..."
apt update -y && apt upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
install_package "curl" "curl" "apt install -y --no-install-recommends curl"
install_package "wget" "wget" "apt install -y --no-install-recommends wget"
install_package "software-properties-common" "software-properties-common" "apt install -y --no-install-recommends software-properties-common"
install_package "pciutils" "pciutils" "apt install -y --no-install-recommends pciutils"
install_package "jq" "jq" "apt install -y --no-install-recommends jq"
install_package "python3" "python3" "apt install -y --no-install-recommends python3"
install_package "python3-pip" "python3-pip" "apt install -y --no-install-recommends python3-pip"
install_package "python3-venv" "python3-venv" "apt install -y --no-install-recommends python3-venv"

# install drivers
install_package "libcudnn8" "libcudnn8" "apt install -y --no-install-recommends libcudnn8"


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
    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
    sudo dpkg -i cuda-keyring_1.1-1_all.deb
    sudo apt-get update
    sudo apt-get -y install cuda-toolkit-12-9
    sudo apt-get install -y cuda-drivers
        
    # Set up TensorFlow GPU
    # install_package "Python Virtual Env" "virtualenv" "pip install virtualenv"
    python3 -m venv /tmp/tf_gpu_env
    source /tmp/tf_gpu_env/bin/activate
    pip install --upgrade pip
    # pip install tensorflow

    REQUIRED_PIP_PACKAGES=(
    "tensorflow==2.18.0"
    "nvidia-cuda-runtime-cu12"
    "nvidia-cudnn-cu12"
    "nvidia-cublas-cu12"
    "matplotlib"
    "pandas"
    )

    for pkg in "${REQUIRED_PIP_PACKAGES[@]}"; do
        if ! pip show $(echo "$pkg" | cut -d= -f1) &>/dev/null; then
            echo "🔧 Installing $pkg..."
            pip install "$pkg"
            jq --arg key "$pkg" --arg value "Installed" '.preparation.pip[$key] = $value' "$JSON_FILE" > temp.json && mv temp.json "$JSON_FILE"
        else
            echo "✅ $pkg already installed."
            jq --arg key "$pkg" --arg value "Already Installed" '.preparation.pip[$key] = $value' "$JSON_FILE" > temp.json && mv temp.json "$JSON_FILE"
        fi
    done
fi

echo "✅ Installation complete. Exiting without running benchmarks."
exit 0


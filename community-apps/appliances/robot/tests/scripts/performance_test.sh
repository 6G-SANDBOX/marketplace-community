#!/bin/bash

# Set non-interactive mode
export DEBIAN_FRONTEND=noninteractive

# Log files
LOG_FILE="benchmark_results_$(date +%Y%m%d_%H%M%S).log"
JSON_FILE="benchmark_data_$(date +%Y%m%d_%H%M%S).json"

source /tmp/tf_gpu_env/bin/activate

# Ensure pip and required packages are installed
python -m pip install --upgrade pip

REQUIRED_PIP_PACKAGES=(
    "tensorflow==2.18.0"
    "nvidia-cuda-runtime-cu12"
    "nvidia-cudnn-cu12"
    "nvidia-cublas-cu12"
)

for pkg in "${REQUIRED_PIP_PACKAGES[@]}"; do
    if ! pip show $(echo "$pkg" | cut -d= -f1) &>/dev/null; then
        echo "🔧 Installing $pkg..."
        pip install "$pkg"
    else
        echo "✅ $pkg already installed."
    fi
done

# Check if libcudnn8 (system-wide) is installed
if ! dpkg -s libcudnn8 &>/dev/null; then
    echo "🔧 Installing libcudnn8..."
    sudo apt-get update && sudo apt-get install -y libcudnn8
else
    echo "✅ libcudnn8 already installed."
fi

# Create JSON file with initial structure
echo "{}" > "$JSON_FILE"

# Function to execute benchmarks and store structured data
run_benchmark() {
    TEST_NAME=$1
    COMMAND=$2
    KEY_NAME=$3

    echo -e "\n�� Running $TEST_NAME benchmark..." | tee -a $LOG_FILE
    RESULT=$(eval $COMMAND 2>&1 | tee -a $LOG_FILE)

    if [[ $? -ne 0 ]]; then
        echo "❌ ERROR: $TEST_NAME benchmark failed!" | tee -a $LOG_FILE
        jq --arg key "$KEY_NAME" --arg value "Failed" '.[$key] = $value' "$JSON_FILE" > temp.json && mv temp.json "$JSON_FILE"
    else
        VALUE=$(echo "$RESULT" | grep -o -E '[0-9]+(\.[0-9]+)?' | tail -1)
        jq --arg key "$KEY_NAME" --arg value "$VALUE" '.[$key] = $value' "$JSON_FILE" > temp.json && mv temp.json "$JSON_FILE"
    fi

    echo "✅ Completed $TEST_NAME benchmark." | tee -a $LOG_FILE
    echo "------------------------------------------------" | tee -a $LOG_FILE
}

sysbench_cpu() {

    # Ejecutar sysbench y capturar salida
    SB_OUT=$(sysbench --threads=$(nproc) cpu --cpu-max-prime=20000 run)

    # Extraer valores clave
    CPU_SPEED=$(echo "$SB_OUT" | awk '/events per second:/ {print $NF}')
    TOTAL_TIME=$(echo "$SB_OUT" | awk '/total time:/ {print $NF}' | sed 's/s//')
    TOTAL_EVENTS=$(echo "$SB_OUT" | awk '/total number of events:/ {print $NF}')

    LAT_MIN=$(echo "$SB_OUT" | awk '/min:/ {print $2}')
    LAT_AVG=$(echo "$SB_OUT" | awk '/avg:/ {print $2}')
    LAT_MAX=$(echo "$SB_OUT" | awk '/max:/ {print $2}')
    LAT_95=$(echo "$SB_OUT" | awk '/95th percentile:/ {print $3}')
    LAT_SUM=$(echo "$SB_OUT" | awk '/sum:/ {print $2}')

    EVENTS_AVG=$(echo "$SB_OUT" | awk '/events \(avg\/stddev\):/ {split($2,a,"/"); print a[1]}')
    EVENTS_STD=$(echo "$SB_OUT" | awk '/events \(avg\/stddev\):/ {split($2,a,"/"); print a[2]}')

    EXEC_AVG=$(echo "$SB_OUT" | awk '/execution time \(avg\/stddev\):/ {split($2,a,"/"); print a[1]}')
    EXEC_STD=$(echo "$SB_OUT" | awk '/execution time \(avg\/stddev\):/ {split($2,a,"/"); print a[2]}')

    sysbench_json=$(jq -n \
        --arg cpu_speed "$CPU_SPEED" \
        --arg total_time "$TOTAL_TIME" \
        --arg total_events "$TOTAL_EVENTS" \
        --arg lat_min "$LAT_MIN" \
        --arg lat_avg "$LAT_AVG" \
        --arg lat_max "$LAT_MAX" \
        --arg lat_95 "$LAT_95" \
        --arg lat_sum "$LAT_SUM" \
        --arg events_avg "$EVENTS_AVG" \
        --arg events_std "$EVENTS_STD" \
        --arg exec_avg "$EXEC_AVG" \
        --arg exec_std "$EXEC_STD" \
        '{
            cpu_speed: $cpu_speed,
            total_time: $total_time,
            total_events: $total_events,
            latency_ms: {
                min: $lat_min,
                avg: $lat_avg,
                max: $lat_max,
                percentile_95: $lat_95,
                sum: $lat_sum
            },
            threads_fairness: {
                events_avg: $events_avg,
                events_stddev: $events_std,
                exec_time_avg: $exec_avg,
                exec_time_stddev: $exec_std
            }
        }')
    jq --arg key "cpu_sysbench" --arg value "$sysbench_json" '.[$key] = $value' "$JSON_FILE" > temp.json && mv temp.json "$JSON_FILE"
}
# # Generar JSON
# cat <<EOF
# {
#   "cpu_speed_events_per_sec": ${CPU_SPEED},
#   "total_time_sec": ${TOTAL_TIME},
#   "total_events": ${TOTAL_EVENTS},
#   "latency_ms": {
#     "min": ${LAT_MIN},
#     "avg": ${LAT_AVG},
#     "max": ${LAT_MAX},
#     "percentile_95": ${LAT_95},
#     "sum": ${LAT_SUM}
#   },
#   "threads_fairness": {
#     "events_avg": ${EVENTS_AVG},
#     "events_stddev": ${EVENTS_STD},
#     "exec_time_avg": ${EXEC_AVG},
#     "exec_time_stddev": ${EXEC_STD}
#   }
# }
# EOF

# Start logging results
echo "========== Benchmarking Results ==========" > $LOG_FILE
echo "Date: $(date)" | tee -a $LOG_FILE
echo "Machine Info: $(hostnamectl)" | tee -a $LOG_FILE
echo "==========================================" | tee -a $LOG_FILE

# Run CPU benchmarks
# run_benchmark "CPU Sysbench" "sysbench --threads=$(nproc) cpu --cpu-max-prime=20000 run" "cpu_sysbench"
sysbench_cpu
run_benchmark "CPU Stress Test" "stress-ng --cpu $(nproc) --cpu-method all --timeout 60" "cpu_stress"
# stress-ng --cpu 4 --cpu-method all --timeout 60 --metrics-brief -> bogos

# Run GPU benchmarks if GPU is detected
if lspci | grep -i nvidia; then
    run_benchmark "GPU NVIDIA-SMI" "nvidia-smi" "gpu_nvidia_smi"
    # run_benchmark "GPU LuxMark" "luxmark"

    # TensorFlow GPU Stress Test - Matrix Multiplication
    echo "🔹 Running TensorFlow GPU stress test (Matrix Multiplication)..." | tee -a $LOG_FILE
    python3 - <<EOF | tee -a $LOG_FILE
import tensorflow as tf
import time

gpus = tf.config.list_physical_devices('GPU')
if not gpus:
    print("No GPU detected!")
    exit()

def stress_gpu(iterations=1000, size=4096):
    print(f"Running GPU stress test with {iterations} iterations on {size}x{size} matrices...")
    with tf.device('/GPU:0'):
        A = tf.random.normal([size, size])
        B = tf.random.normal([size, size])
        
        start_time = time.time()
        for _ in range(iterations):
            _ = tf.matmul(A, B)
        elapsed_time = time.time() - start_time

    print(f"GPU Stress Test Completed in {elapsed_time:.2f} seconds.")

stress_gpu()
EOF
    echo "✅ TensorFlow GPU stress test completed." | tee -a $LOG_FILE

    # TensorFlow Deep Learning Test - ResNet50
    echo "🔹 Running TensorFlow ResNet50 Training Benchmark..." | tee -a $LOG_FILE
    python3 - <<EOF | tee -a $LOG_FILE
import tensorflow as tf
from tensorflow.keras.applications import ResNet50
import time

with tf.device('/GPU:0'):
    model = ResNet50(weights=None, input_shape=(224, 224, 3), classes=1000)
    model.compile(optimizer='adam', loss='categorical_crossentropy')

    x_train = tf.random.normal([32, 224, 224, 3])
    y_train = tf.random.uniform([32, 1000], maxval=1)

    start_time = time.time()
    model.fit(x_train, y_train, epochs=10, batch_size=32, verbose=1)
    elapsed_time = time.time() - start_time

print(f"ResNet50 Training Completed in {elapsed_time:.2f} seconds.")
EOF
    echo "✅ TensorFlow ResNet50 Training Benchmark completed." | tee -a $LOG_FILE
fi


# Run storage benchmarks
run_benchmark "Disk Read/Write Performance (FIO)" "fio --name=randwrite --ioengine=libaio --rw=randwrite --bs=4k --numjobs=4 --size=1G --runtime=60 --time_based --group_reporting --unlink=1" "fio_randwrite"

# Dynamically detect root device (e.g., /dev/sda, /dev/vda, /dev/nvme0n1)
ROOT_DEV=$(df / | tail -1 | awk '{print $1}')
BLOCK_DEV=$(lsblk -no pkname "$ROOT_DEV" 2>/dev/null | head -n 1)

# Fallback if lsblk fails (e.g., on LVM/loop)
if [ -z "$BLOCK_DEV" ]; then
    BLOCK_DEV=$(basename "$ROOT_DEV")
fi

# Prepend /dev/ if needed
if [[ ! "$BLOCK_DEV" =~ ^/dev/ ]]; then
    BLOCK_DEV="/dev/$BLOCK_DEV"
fi

# Check if the device exists
if [ -b "$BLOCK_DEV" ]; then
    run_benchmark "Disk Read Speed (Hdparm)" "hdparm -Tt $BLOCK_DEV" "hdparm_read_speed"
else
    echo "⚠️  Warning: Could not determine root block device for hdparm test." | tee -a $LOG_FILE
    jq --arg key "hdparm_read_speed" --arg value "Device detection failed" '.[$key] = $value' "$JSON_FILE" > temp.json && mv temp.json "$JSON_FILE"
fi

# Clean up leftover files from FIO or others
rm -f randwrite* *.fio

# Run RAM benchmark
run_benchmark "Memory Test (Memtester)" "memtester 512M 1" "memtester"

# Run network benchmarks
run_benchmark "Network Performance (Iperf3 - Download)" "iperf3 -c iperf.he.net -t 10" "iperf3_download"
run_benchmark "Network Performance (Iperf3 - Upload)" "iperf3 -c iperf.he.net -t 10 -R" "iperf3_upload"

# Completion message
echo "✅ All benchmarks completed. Results saved in $LOG_FILE"

# Completion message
echo "✅ All benchmarks completed. Results saved in $LOG_FILE and $JSON_FILE"
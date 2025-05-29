#!/bin/bash

# Set non-interactive mode
export DEBIAN_FRONTEND=noninteractive

# Iperf3 server configuration
IPERF3_SERVER="10.95.82.70"  # You can change this to your desired server IP or hostname

# Default is to run memory test
RUN_MEMTEST=true

# Parse optional argument --no-memtest
for arg in "$@"; do
    case $arg in
        --no-memtest)
        RUN_MEMTEST=false
        shift
        ;;
    esac
done

# Log files
LOG_FILE="benchmark_results_$(date +%Y%m%d_%H%M%S).log"
JSON_FILE="benchmark_data_$(date +%Y%m%d_%H%M%S).json"

# plot files
GPU_MONITOR_LOG="/tmp/gpu_monitor.csv"
GPU_PLOT_FILE="gpu_usage_plot.png"

source /tmp/tf_gpu_env/bin/activate

# Ensure pip and required packages are installed
python -m pip install --upgrade pip

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

    # Execute sysbench and get the output
    SB_OUT=$(sysbench --threads=$(nproc) cpu --cpu-max-prime=20000 run)

    # extract relevant metrics from sysbench output
    CPU_SPEED=$(echo "$SB_OUT" | awk '/events per second:/ {print $NF}')
    TOTAL_TIME=$(echo "$SB_OUT" | awk '/total time:/ {print $NF}' | sed 's/s//')
    TOTAL_EVENTS=$(echo "$SB_OUT" | awk '/total number of events:/ {print $NF}')

    LAT_MIN=$(echo "$SB_OUT" | awk '/min:/ {print $2}')
    LAT_AVG=$(echo "$SB_OUT" | awk '/avg:/ {print $2}')
    LAT_MAX=$(echo "$SB_OUT" | awk '/max:/ {print $2}')
    LAT_95=$(echo "$SB_OUT" | awk '/95th percentile:/ {print $3}')
    LAT_SUM=$(echo "$SB_OUT" | awk '/sum:/ {print $2}')

    EVENTS_AVG=$(echo "$SB_OUT" | grep "events (avg/stddev):" | sed -E 's/.*: *([0-9.]+)\/[0-9.]+/\1/')
    EVENTS_STD=$(echo "$SB_OUT" | grep "events (avg/stddev):" | sed -E 's/.*: *[0-9.]+\/([0-9.]+)/\1/')

    EXEC_AVG=$(echo "$SB_OUT" | grep "execution time (avg/stddev):" | sed -E 's/.*: *([0-9.]+)\/[0-9.]+/\1/')
    EXEC_STD=$(echo "$SB_OUT" | grep "execution time (avg/stddev):" | sed -E 's/.*: *[0-9.]+\/([0-9.]+)/\1/')


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
    echo "$sysbench_json" > /tmp/sysbench_metrics.json
}

generate_json_from_log() {
    echo "🔸 Generating final JSON output from log..."

    # Host info
    HOST_INFO=$(hostnamectl)
    HOSTNAME=$(echo "$HOST_INFO" | grep 'Static hostname' | awk '{print $3}' || echo "unknown")
    OS=$(echo "$HOST_INFO" | grep 'Operating System' | cut -d: -f2- | xargs || echo "unknown")
    KERNEL=$(echo "$HOST_INFO" | grep 'Kernel' | cut -d: -f2- | xargs || echo "unknown")
    ARCH=$(echo "$HOST_INFO" | grep 'Architecture' | cut -d: -f2- | xargs || echo "unknown")
    VIRT=$(echo "$HOST_INFO" | grep 'Virtualization' | cut -d: -f2- | xargs || echo "unknown")
    MODEL=$(echo "$HOST_INFO" | grep 'Hardware Model' | cut -d: -f2- | xargs || echo "unknown")

    # GPU Info
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1 || echo "unknown")
    GPU_MEM=$(grep "MiB /" "$LOG_FILE" | awk '{print $9}' | cut -d'/' -f2 | tr -d 'MiB')
    GPU_TEMP=$(grep -m1 'C    P' "$LOG_FILE" | awk '{print $3}' | tr -d 'C')
    GPU_UTIL=$(grep -m1 'C    P' "$LOG_FILE" | awk '{print $(NF-5)}' | tr -d '%')
    TF_GPU_ITER=$(grep "Running GPU stress test with" "$LOG_FILE" | awk '{for(i=1;i<=NF;i++) if ($i=="with") print $(i+1)}' | head -n1)
    RESNET_TIME=$(grep "ResNet50 Training Completed" "$LOG_FILE" | awk '{print $(NF-1)}')
    TF_GPU_MATRIX=$(grep "Running GPU stress test with" "$LOG_FILE" | sed -n 's/.*on \([0-9]\+x[0-9]\+\) matrices.*/\1/p')
    TF_GPU_ITER=$(echo "${TF_GPU_ITER:-0}" | grep -Eo '^[0-9]+$' || echo "0")

    # Extract loss values from training log
    RESNET_LOSS=()
    while IFS= read -r line; do
        LOSS_VAL=$(echo "$line" | grep -oE 'loss:[[:space:]]*[0-9.]+' | awk -F ':' '{print $2}' | xargs)
        if [[ "$LOSS_VAL" =~ ^[0-9.]+$ ]]; then
            RESNET_LOSS+=("$LOSS_VAL")
        fi
    done < <(grep -E 'loss:[[:space:]]*[0-9.]+' "$LOG_FILE")


    # Write to a JSON array file for use in jq
    LOSS_FILE="/tmp/loss_array.json"
    if [ "${#RESNET_LOSS[@]}" -gt 0 ]; then
        printf '%s\n' "${RESNET_LOSS[@]}" | jq -R 'select(test("^[0-9.eE+-]+$")) | tonumber' | jq -s . > "$LOSS_FILE"
    else
        echo "[]" > "$LOSS_FILE"
fi


    # Disk
    IOPS=$(grep "IOPS=" "$LOG_FILE" | awk -F'IOPS=' '{print $2}' | awk -F',' '{print $1}' | head -n1)
    FIO_BW=$(grep "BW=" "$LOG_FILE" | awk -F'BW=' '{print $2}' | awk '{print $1}' | head -n1)
    FIO_LAT=$(grep "avg=" "$LOG_FILE" | grep "lat" | head -n1 | awk '{print $3}')
    CACHED_READ=$(grep "Timing cached reads" "$LOG_FILE" | awk -F '=' '{print $2}' | awk '{print $1}')
    BUFFERED_READ=$(grep "Timing buffered disk reads" "$LOG_FILE" | awk -F '=' '{print $2}' | awk '{print $1}')
    HDPARM_DEV=$(grep '^/dev/' "$LOG_FILE" | head -n 1 | awk -F: '{print $1}')
    # Disk - Enhanced FIO parsing
    FIO_BLOCK=$(awk '/Running Disk Read\/Write Performance \(FIO\) benchmark/,/Completed Disk Read\/Write Performance \(FIO\) benchmark/' "$LOG_FILE")
    FIO_IOPS=$(echo "$FIO_BLOCK" | grep -oP 'iops\s+:.*avg=\K[0-9.]+' | head -1)
    FIO_BW=$(echo "$FIO_BLOCK" | grep -oP 'write: IOPS=.*BW=\K[0-9.]+' | head -1)
    FIO_LATENCY=$(echo "$FIO_BLOCK" | grep -oP 'lat \(usec\):.*avg=\K[0-9.]+' | head -1)
    FIO_P99=$(echo "$FIO_BLOCK" | grep -A15 'clat percentiles' | grep '99.00th' | grep -oP '\[\K[0-9.]+' | head -1)
    FIO_CPU_USR=$(echo "$FIO_BLOCK" | grep -oP 'cpu\s+: usr=\K[0-9.]+' | head -1)
    FIO_CPU_SYS=$(echo "$FIO_BLOCK" | grep -oP 'cpu\s+:.*sys=\K[0-9.]+' | head -1)
 
    # Fallback defaults
    FIO_IOPS=${FIO_IOPS:-0}
    FIO_BW=${FIO_BW:-0}
    FIO_LATENCY=${FIO_LATENCY:-0}
    FIO_P99=$(awk "BEGIN {print (${FIO_P99:-0} / 1000)}")  # convert nsec to usec
    FIO_CPU_USR="${FIO_CPU_USR:-0}%"
    FIO_CPU_SYS="${FIO_CPU_SYS:-0}%"
    # Memory
    MEM_OK=$(grep -A20 "Memory Test" "$LOG_FILE" | grep -c "ok")
    MEM_STATUS="ok"
    if [ "$MEM_OK" -lt 18 ]; then MEM_STATUS="partial"; fi


    # Download block (receiver + sender)
    IPERF3_DOWN_BLOCK=$(awk '/Running Network Performance \(Iperf3 - Download\) benchmark/,/Completed Network Performance \(Iperf3 - Download\) benchmark/' "$LOG_FILE")

    # Upload block (receiver + sender)
    IPERF3_UP_BLOCK=$(awk '/Running Network Performance \(Iperf3 - Upload\) benchmark/,/Completed Network Performance \(Iperf3 - Upload\) benchmark/' "$LOG_FILE")

    # Extract final download bandwidth (receiver)
    NET_DOWN=$(echo "$IPERF3_DOWN_BLOCK" | awk '/receiver$/ {print $(NF-2) " " $(NF-1)}' | tail -n1)

    # Extract final upload bandwidth (receiver)
    NET_UP=$(echo "$IPERF3_UP_BLOCK" | awk '/receiver$/ {print $(NF-2) " " $(NF-1)}' | tail -n1)

    # Extract download retransmissions (sender line ending with 'sender')
    NET_RETRANS_DOWN=$(echo "$IPERF3_DOWN_BLOCK" | awk '/sender$/ {print $(NF-1)}' | tail -n1)

    # Extract upload retransmissions (sender line ending with 'sender')
    NET_RETRANS_UP=$(echo "$IPERF3_UP_BLOCK" | awk '/sender$/ {print $(NF-1)}' | tail -n1)

    # Set fallbacks
    NET_DOWN=${NET_DOWN:-"unavailable"}
    NET_UP=${NET_UP:-"unavailable"}
    NET_RETRANS_DOWN=${NET_RETRANS_DOWN:-"unavailable"}
    NET_RETRANS_UP=${NET_RETRANS_UP:-"unavailable"}

    # Sanitize and set defaults
    GPU_NAME=${GPU_NAME:-"none"}
    GPU_MEM=$(echo "${GPU_MEM:-0}" | grep -Eo '^[0-9]+(\.[0-9]+)?$' || echo "0")
    GPU_TEMP=$(echo "${GPU_TEMP:-0}" | grep -Eo '^[0-9]+(\.[0-9]+)?$' || echo "0")
    GPU_UTIL=$(echo "${GPU_UTIL:-0}" | grep -Eo '^[0-9]+(\.[0-9]+)?$' || echo "0")
    TF_GPU_TIME=$(grep "GPU Stress Test Completed" "$LOG_FILE" | grep -Eo '[0-9]+\.[0-9]+' | tail -1)
    RESNET_TIME=$(echo "${RESNET_TIME:-0}" | grep -Eo '^[0-9]+(\.[0-9]+)?$' || echo "0")
    IOPS=$(echo "${IOPS:-0}" | grep -Eo '^[0-9]+(\.[0-9]+)?$' || echo "0")
    FIO_BW=$(echo "${FIO_BW:-0}" | grep -Eo '^[0-9]+(\.[0-9]+)?$' || echo "0")
    FIO_LAT=$(echo "${FIO_LAT:-0}" | grep -Eo '^[0-9]+(\.[0-9]+)?$' || echo "0")
    CACHED_READ=$(echo "${CACHED_READ:-0}" | grep -Eo '^[0-9]+(\.[0-9]+)?$' || echo "0")
    BUFFERED_READ=$(echo "${BUFFERED_READ:-0}" | grep -Eo '^[0-9]+(\.[0-9]+)?$' || echo "0")
    HDPARM_DEV=${HDPARM_DEV:-"/dev/unknown"}

    # Collect CPU information
    CPU_MODEL=$(lscpu | grep -i 'Model name' | awk -F: '{print $2}' | xargs)
    CPU_CORES=$(lscpu | grep "^Core(s) per socket:" | awk '{print $4}')
    SOCKETS=$(lscpu | grep "^Socket(s):" | awk '{print $2}')
    THREADS=$(nproc)
    CPU_FREQ=$(awk -F: '/cpu MHz/ {print $2; exit}' /proc/cpuinfo | xargs)
    CACHE_SIZE=$(lscpu | grep "L3 cache" | awk -F: '{print $2}' | tr -d '[:space:]' | sed 's/K//')
    SYSBENCH_JSON=$(cat /tmp/sysbench_metrics.json)

    # Parse stress-ng output from log
    STRESS_LOG=$(awk '/Running CPU Stress Test benchmark/,/Completed CPU Stress Test benchmark/' "$LOG_FILE")

    STRESS_WORKERS=$(echo "$STRESS_LOG" | grep "dispatching hogs" | grep -oE '[0-9]+ cpu' | awk '{print $1}')
    STRESS_SKIPPED=$(echo "$STRESS_LOG" | grep "skipped:" | awk '{print $NF}')
    STRESS_PASSED=$(echo "$STRESS_LOG" | grep "passed:" | grep -oE 'passed: [0-9]+' | awk '{print $2}')
    STRESS_FAILED=$(echo "$STRESS_LOG" | grep "failed:" | awk '{print $NF}')
    STRESS_UNTRUST=$(echo "$STRESS_LOG" | grep "metrics untrustworthy:" | awk '{print $NF}')
    STRESS_DURATION=$(echo "$STRESS_LOG" | grep "successful run completed" | grep -oE '[0-9]+\.[0-9]+' | tail -1)

    # Set defaults if missing
    STRESS_WORKERS=${STRESS_WORKERS:-0}
    STRESS_SKIPPED=${STRESS_SKIPPED:-0}
    STRESS_PASSED=${STRESS_PASSED:-0}
    STRESS_FAILED=${STRESS_FAILED:-0}
    STRESS_UNTRUST=${STRESS_UNTRUST:-0}
    STRESS_DURATION=${STRESS_DURATION:-0}

    jq --slurpfile loss_list "$LOSS_FILE" -n \
        --arg hostname "$HOSTNAME" \
        --arg os "$OS" \
        --arg kernel "$KERNEL" \
        --arg arch "$ARCH" \
        --arg virt "$VIRT" \
        --arg model "$MODEL" \
        --arg gpu "$GPU_NAME" \
        --argjson gpu_mem "$GPU_MEM" \
        --argjson gpu_temp "$GPU_TEMP" \
        --argjson gpu_util "$GPU_UTIL" \
        --argjson tf_gpu_time "$TF_GPU_TIME" \
        --argjson resnet_time "$RESNET_TIME" \
        --argjson tf_gpu_iterations "$TF_GPU_ITER" \
        --argjson loss_list "$LOSS_JSON" \
        --argjson fio_iops "$FIO_IOPS" \
        --argjson fio_bw "$FIO_BW" \
        --argjson fio_lat "$FIO_LATENCY" \
        --argjson fio_p99 "$FIO_P99" \
        --arg fio_cpu_usr "$FIO_CPU_USR" \
        --arg fio_cpu_sys "$FIO_CPU_SYS" \
        --argjson cached_read "$CACHED_READ" \
        --argjson buffered_read "$BUFFERED_READ" \
        --arg tf_gpu_matrix "$TF_GPU_MATRIX" \
        --arg hdparm_dev "$HDPARM_DEV" \
        --arg mem_status "$MEM_STATUS" \
        --arg net_down "$NET_DOWN" \
        --arg net_up "$NET_UP" \
        --arg net_retrans_down "$NET_RETRANS_DOWN" \
        --arg net_retrans_up "$NET_RETRANS_UP" \
        --arg cpu_model "$CPU_MODEL" \
        --argjson cpu_cores "$CPU_CORES" \
        --argjson sockets "$SOCKETS" \
        --argjson threads "$THREADS" \
        --arg cpu_freq_mhz "$CPU_FREQ" \
        --arg cache_size_kb "$CACHE_SIZE" \
        --argjson cpu "$SYSBENCH_JSON" \
        --argjson stress_workers "$STRESS_WORKERS" \
        --argjson stress_skipped "$STRESS_SKIPPED" \
        --argjson stress_passed "$STRESS_PASSED" \
        --argjson stress_failed "$STRESS_FAILED" \
        --argjson stress_untrust "$STRESS_UNTRUST" \
        --argjson stress_duration "$STRESS_DURATION" \
        '{
            machine_info: {
                hostname: $hostname,
                os: $os,
                kernel: $kernel,
                arch: $arch,
                virtualization: $virt,
                hardware_model: $model,
                "cpu_info": {
                  "model": $cpu_model,
                  "cores_per_socket": $cpu_cores,
                  "sockets": $sockets,
                  "threads": $threads,
                  "cpu_freq_mhz": $cpu_freq_mhz,
                  "l3_cache_kb": $cache_size_kb,
                  "stress_ng": {
                    "cpu_workers": $stress_workers,
                    "skipped": $stress_skipped,
                    "passed": $stress_passed,
                    "failed": $stress_failed,
                    "metrics_untrustworthy": $stress_untrust,
                    "duration_sec": $stress_duration
                  },
                  "sysbench_metrics": $cpu
                }
            },
            gpu: {
                name: $gpu,
                memory_total_mib: $gpu_mem,
                temperature_c: $gpu_temp,
                utilization_gpu_percent: $gpu_util,
                tensorflow_gpu_stress: {
                  time_sec: $tf_gpu_time,
                  iterations: $tf_gpu_iterations,
                  matrix_size: $tf_gpu_matrix
                },
                resnet50_training: {
                  total_time_sec: $resnet_time,
                  "loss_per_epoch": $loss_list[0]
                }
            },
            disk: {
                fio_randwrite: {
                    iops: $fio_iops,
                    bandwidth_mib_s: $fio_bw,
                    latency_avg_usec: $fio_lat,
                    clat_99th_percentile_usec: $fio_p99,
                    cpu_usage_percent: {
                        user: $fio_cpu_usr,
                        system: $fio_cpu_sys
                    }                    
                },
                hdparm: {
                    cached_read_mb_s: $cached_read,
                    buffered_disk_read_mb_s: $buffered_read,
                    device_tested: $hdparm_dev
                }
            },
            memory: {
                memtester_512mb: $mem_status
            },
            network: {
                iperf3_download: $net_down,
                iperf3_upload: $net_up,
                retransmissions: {
                    download: $net_retrans_down,
                    upload: $net_retrans_up
                }
            }
        }' > "$JSON_FILE"

    echo "✅ JSON file generated: $JSON_FILE"
}

# Start logging results
echo "========== Benchmarking Results ==========" > $LOG_FILE
echo "Date: $(date)" | tee -a $LOG_FILE
echo "Machine Info: $(hostnamectl)" | tee -a $LOG_FILE
echo "==========================================" | tee -a $LOG_FILE

# Run CPU benchmarks
sysbench_cpu
run_benchmark "CPU Stress Test" "stress-ng --cpu $(nproc) --cpu-method all --timeout 60" "cpu_stress"

# Run GPU benchmarks if GPU is detected
if lspci | grep -i nvidia; then
    run_benchmark "GPU NVIDIA-SMI" "nvidia-smi" "gpu_nvidia_smi"

    # start monitoring
    nvidia-smi --query-gpu=timestamp,utilization.gpu,utilization.memory,memory.used,memory.total,temperature.gpu \
    --format=csv,noheader,nounits -l 1 > "$GPU_MONITOR_LOG" &
    GPU_MONITOR_PID=$!

    # TensorFlow GPU Stress Test - Matrix Multiplication
    echo "🔹 Running TensorFlow GPU stress test (Matrix Multiplication)..." | tee -a $LOG_FILE
    TF_LOG="/tmp/tf_output.log"
    python3 - <<EOF > "$TF_LOG"
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
    # Append TensorFlow logs to the main log
    cat "$TF_LOG" >> "$LOG_FILE"

    # TensorFlow Deep Learning Test - ResNet50
    echo "🔹 Running TensorFlow ResNet50 Training Benchmark..." | tee -a $LOG_FILE
    # Run ResNet50 test similarly, log to file, append to main log
    RESNET_LOG="/tmp/resnet_output.log"
    python3 - <<EOF > "$RESNET_LOG"
import tensorflow as tf
from tensorflow.keras.applications import ResNet50
import time

with tf.device('/GPU:0'):
    model = ResNet50(weights=None, input_shape=(224, 224, 3), classes=1000)
    model.compile(optimizer='adam', loss='categorical_crossentropy')

    x_train = tf.random.normal([32, 224, 224, 3])
    y_train = tf.random.uniform([32, 1000], maxval=1)

    start_time = time.time()
    model.fit(x_train, y_train, epochs=10, batch_size=32, verbose=2)
    elapsed_time = time.time() - start_time

print(f"ResNet50 Training Completed in {elapsed_time:.2f} seconds.")
EOF
    echo "✅ TensorFlow ResNet50 Training Benchmark completed." | tee -a $LOG_FILE
    cat "$RESNET_LOG" >> "$LOG_FILE"

    # Stop monitoring
    kill $GPU_MONITOR_PID

python3 - <<EOF
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.dates as mdates

plt.style.use("seaborn-v0_8-whitegrid")  # Clean grid style

log_file = "$GPU_MONITOR_LOG"
plot_file = "$GPU_PLOT_FILE"

try:
    df = pd.read_csv(log_file, names=[
        "timestamp", "util_gpu", "util_mem", "mem_used", "mem_total", "temp"
    ])
    df["timestamp"] = pd.to_datetime(df["timestamp"], errors="coerce")
    df.dropna(subset=["timestamp"], inplace=True)
    df["mem_percent"] = df["mem_used"] / df["mem_total"] * 100

    fig, ax = plt.subplots(figsize=(14, 6), dpi=300)

    ax.plot(df["timestamp"], df["util_gpu"], label="GPU Utilization (%)", linewidth=2.5)
    ax.plot(df["timestamp"], df["mem_percent"], label="Memory Usage (%)", linewidth=2.5)
    ax.plot(df["timestamp"], df["temp"], label="GPU Temp (°C)", linewidth=2.5)

    ax.set_xlabel("Time", fontsize=12)
    ax.set_ylabel("Percentage / Temperature", fontsize=12)
    ax.set_title("GPU Monitoring During TensorFlow Tests", fontsize=14)

    ax.xaxis.set_major_formatter(mdates.DateFormatter("%H:%M:%S"))
    plt.xticks(rotation=45)
    plt.yticks(fontsize=10)
    plt.xticks(fontsize=10)

    ax.legend(loc="upper left", fontsize=10, frameon=True, edgecolor="gray")
    ax.grid(True, linestyle="--", linewidth=0.5, alpha=0.7)

    plt.tight_layout()
    plt.savefig(plot_file, bbox_inches="tight", facecolor="white")
    print(f"✅ GPU plot saved to: {plot_file}")
except Exception as e:
    print(f"❌ Error generating GPU plot: {e}")
EOF



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
if [ "$RUN_MEMTEST" = true ]; then
    run_benchmark "Memory Test (Memtester)" "memtester 512M 1" "memtester"
else
    echo "⚠️  Skipping Memory Test (Memtester) as per configuration." | tee -a "$LOG_FILE"
fi

# Network - Download
echo "�� Running Network Performance (Iperf3 - Download) benchmark..." | tee -a $LOG_FILE
iperf3 -c "$IPERF3_SERVER" -t 10 2>&1 | tee -a $LOG_FILE
echo "✅ Completed Network Performance (Iperf3 - Download) benchmark." | tee -a $LOG_FILE
echo "------------------------------------------------" | tee -a $LOG_FILE

# Network - Upload
echo "�� Running Network Performance (Iperf3 - Upload) benchmark..." | tee -a $LOG_FILE
iperf3 -c "$IPERF3_SERVER" -t 10 -R 2>&1 | tee -a $LOG_FILE
echo "✅ Completed Network Performance (Iperf3 - Upload) benchmark." | tee -a $LOG_FILE
echo "------------------------------------------------" | tee -a $LOG_FILE


# Completion message
echo "✅ All benchmarks completed. Results saved in $LOG_FILE"

# Completion message
echo "✅ All benchmarks completed. Results saved in $LOG_FILE and $JSON_FILE"

generate_json_from_log
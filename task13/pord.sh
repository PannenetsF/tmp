#!/bin/bash

# Check if config file is provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <config_file> <pd_config_file>"
    exit 1
fi

# Load environment variables from the config file
source ~/.bashrc
source $1
source $2

# MPI specific variables
RANK=$OMPI_COMM_WORLD_RANK
SIZE=$OMPI_COMM_WORLD_SIZE

# Calculate instances per node
_total_instance_num=$((PREFILL_INSTANCE_NUM + DECODE_INSTANCE_NUM))
_ratio=$((_total_instance_num / 8))
PREFILL_INSTANCE_NUM_PER_NODE=$((PREFILL_INSTANCE_NUM / _ratio))
DECODE_INSTANCE_NUM_PER_NODE=$((DECODE_INSTANCE_NUM / _ratio))

# Validate instance numbers
if [ $((_total_instance_num % 8)) -ne 0 ]; then
    echo "Total instance number must be a multiple of 8."
    exit 1
fi
if [ $((PREFILL_INSTANCE_NUM % DECODE_INSTANCE_NUM)) -ne 0 ] && [ $((DECODE_INSTANCE_NUM % PREFILL_INSTANCE_NUM)) -ne 0 ]; then
    echo "Prefill instance number must be a multiple of decode instance number, or vice versa."
    exit 1
fi
if [ $((PREFILL_INSTANCE_NUM % 2)) -ne 0 ] || [ $((DECODE_INSTANCE_NUM % 2)) -ne 0 ]; then
    echo "Prefill and decode instance numbers must be even."
    exit 1
fi

# Function to get the IP address for the current host
get_host_ip() {
    local hostname=$(hostname)
    for i in "${!ALL_HOSTS[@]}"; do
        if [[ "${ALL_HOSTS[$i]}" = "${hostname}" ]]; then
            echo "${ALL_IPS[$i]}"
            return
        fi
    done
    echo "127.0.0.1"  # Fallback to localhost if not found
}

# Get the IP address for this host
HOST_IP=$(get_host_ip)

# Function to get mode (prefill or decode) based on instance index
get_mode() {
    local idx=$1
    idx=$((idx % 8))
    if [ $idx -lt $PREFILL_INSTANCE_NUM_PER_NODE ]; then
        echo "prefill"
    else
        echo "decode"
    fi
}
get_mode_idx() {
    local idx=$1
    local prefill_per_node=$PREFILL_INSTANCE_NUM_PER_NODE
    local node_rank=$((idx / 8))  # 当前是第几个节点
    local local_idx=$((idx % 8))  # 当前节点的索引

    if [ $local_idx -lt $prefill_per_node ]; then
        # prefill 情况下的 real_idx
        real_idx=$((node_rank * prefill_per_node + local_idx))
        echo $real_idx
    else
        # decode 情况下的 real_idx
        real_idx=$((node_rank * (8 - prefill_per_node) + (local_idx - prefill_per_node)))
        echo $real_idx
    fi
}


# Determine instance parameters based on rank
mode=$(get_mode $RANK)
real_idx=$(get_mode_idx $RANK)
if [ "$mode" == "prefill" ]; then
    local_port=$((PREFILL_START_PORT + 20 * real_idx))
    detok_port=$((DETOKENIZATION_FROM_ROUTER_START_PORT + 20 * RANK))
    load_port=$((PREFILL_LOAD_START_PORT + 20 * real_idx))
else
    local_port=$((DECODE_START_PORT + 20 * real_idx))
    detok_port=$((DETOKENIZATION_FROM_ROUTER_START_PORT + 20 * RANK))
    load_port=$((DECODE_LOAD_START_PORT + 20 * real_idx))
    sche_port=$((DECODE_SCHEDULER_SOCKET_START_PORT + 20 * real_idx))
fi

# Construct the command
cmd="-m lightllm.server.backend_pord_server \
  --model_dir $MODEL_DIR \
  --max_req_total_len $MAX_REQ_TOTAL_LEN \
  --max_req_input_len $MAX_REQ_INPUT_LEN \
  --max_total_token_num $MAX_TOTAL_TOKEN_NUM \
  --parameter_cache $PARAM_CACHE \
  --host $HOST_IP \
  --tp $TP_PER_INSTANCE \
  --nccl_ip $NCCL_HOST \
  --nccl_port $NCCL_PORT \
  --local_instance_num 8 \
  --instance_id $RANK \
  --instance_num $SIZE \
  --router_socket ${HOST_IP}:${local_port} \
  --detokenization_socket ${CONTROL_HOST}:${detok_port} \
  --dist_mode $mode \
  --socket_server_addr_port ${HOST_IP}:${load_port}"

if [ "$mode" == "prefill" ]; then
    cmd+=" --running_max_req_size 10 \
    --batch_max_tokens $((MAX_REQ_TOTAL_LEN + 10)) \
    --decode_scheduler_url $DECODE_SCHEDULER_URL"
else
    cmd+=" --decode_scheduler_socket ${HOST_IP}:${sche_port}"
fi

log_and_exec() {
    log_file=$1
    shift
    echo "Executing command: $@" | tee -a "$log_file"
    "$@" 2>&1 | tee -a "$log_file" &
}
# Execute the command
echo `hostname` $HOST_IP $RANK 2>&1 | tee $SCRIPT_DIR/log.backend.${mode}.${RANK}
log_and_exec $SCRIPT_DIR/log.backend.${mode}.${RANK} python $cmd 

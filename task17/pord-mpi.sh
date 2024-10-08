#!/bin/bash

# Check if config file is provided
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <config_file> <pd_config_file> <data_source>"
    exit 1
fi

CONFIG_FILE=$1
PD_CONFIG_FILE=$2
DATA_SOURCE=$3

# Source the config file
source $CONFIG_FILE
source $PD_CONFIG_FILE

# Calculate total number of instances
TOTAL_INSTANCE_NUM=$((PREFILL_INSTANCE_NUM + DECODE_INSTANCE_NUM))
echo total mpi procs: $TOTAL_INSTANCE_NUM

# Create a temporary hostfile
HOSTFILE="hostfile.txt"

generate_socket_list() {
    local start_port=$1
    local -a host_array=("${@:2:$#-2}")  # 接受从第2个参数开始直到倒数第2个参数的所有作为数组
    local instance_num=${!#}  # 最后一个参数作为 instance_num
    instance_num=$(( instance_num / ${#host_array[@]} ))  # 计算每个host的实例数量
    local result=""

    for i in $(seq 0 $((${#host_array[@]} * instance_num - 1))); do
        host=${host_array[$((i / instance_num))]}  # 计算当前host
        local_port=$((start_port + 20 * i))  # 计算本地端口
        result+="${host}:${local_port},"  # 拼接结果
    done

    echo "${result%,}"  # 移除最后的逗号
}

generate_single_socket() {
    local start_port=$1
    local ip=$2  # 单个IP
    local instance_num=$3
    local result=""

    for i in $(seq 0 $((instance_num - 1))); do
        local_port=$((start_port + 20 * i))  # 计算本地端口
        result+="${ip}:${local_port},"  # 拼接结果
    done

    echo "${result%,}"  # 移除最后的逗号
}

generate_ids() {
  local prefill_per_node=$1
  local decode_per_node=$2
  local num_of_nodes=$3
  local res=""

  for ((i=0; i<num_of_nodes; i++)); do
    base=$(( (prefill_per_node + decode_per_node) * i + prefill_per_node))  
    for ((j=0; j<decode_per_node; j++)); do
      res+=$((base + j))","  # 添加索引并以逗号分隔
    done
  done

  echo "${res%,}"  # 去除最后一个多余的逗号并输出结果
}

_total_nodes=${#ALL_IPS[@]}
DECODE_INSTANCES_IDS=$(generate_ids $((PREFILL_INSTANCE_NUM/_total_nodes)) $((DECODE_INSTANCE_NUM/_total_nodes)) $_total_nodes)
# Generate socket lists
PREFILL_SOCKETS=$(generate_socket_list $PREFILL_START_PORT ${ALL_IPS[@]} $PREFILL_INSTANCE_NUM)
DECODE_SOCKETS=$(generate_socket_list $DECODE_START_PORT ${ALL_IPS[@]} $DECODE_INSTANCE_NUM)
PREFILL_LOAD_SOCKETS=$(generate_socket_list $PREFILL_LOAD_START_PORT ${ALL_IPS[@]} $PREFILL_INSTANCE_NUM)
DECODE_LOAD_SOCKETS=$(generate_socket_list $DECODE_LOAD_START_PORT ${ALL_IPS[@]} $DECODE_INSTANCE_NUM)
PREFILL_DETOKENIZATION_SOCKETS=$(generate_single_socket $DETOKENIZATION_FROM_ROUTER_START_PORT $CONTROL_HOST $PREFILL_INSTANCE_NUM)
DECODE_DETOKENIZATION_SOCKETS=$(generate_single_socket $((DETOKENIZATION_FROM_ROUTER_START_PORT + 20 * PREFILL_INSTANCE_NUM)) $CONTROL_HOST $DECODE_INSTANCE_NUM)
DETOKENIZATION_FROM_ROUTER_SOCKETS="${PREFILL_DETOKENIZATION_SOCKETS},${DECODE_DETOKENIZATION_SOCKETS}"
DECODE_SCHE_SOCKETS=$(generate_socket_list $DECODE_SCHEDULER_SOCKET_START_PORT ${ALL_IPS[@]} $DECODE_INSTANCE_NUM)


log_and_exec() {
    log_file=$1
    shift
    echo "Executing command: $@" | tee "$log_file"
    "$@" 2>&1 | tee -a "$log_file" &
}

# Launch HTTP server (frontend)
log_and_exec $SCRIPT_DIR/log.frontend python -m lightllm.server.frontend_server --host $CONTROL_HOST --port 9090 \
  --max_req_total_len $MAX_REQ_TOTAL_LEN --max_req_input_len $MAX_REQ_INPUT_LEN --max_total_token_num $MAX_TOTAL_TOKEN_NUM \
  --tokenizer_mode fast --nccl_ip $NCCL_HOST --nccl_port $NCCL_PORT \
  --trust_remote_code \
  --detokenization_recv_from_router_socket $DETOKENIZATION_FROM_ROUTER_SOCKETS \
  --detokenization_send_to_http_sockets ${CONTROL_HOST}:${DETOKENIZATION_TO_HTTP_START_PORT} \
  --prefill_sockets $PREFILL_SOCKETS \
  --detokenization_send_to_midterm_socket ${CONTROL_HOST}:${DETOKENIZATION_TO_MID_START_PORT} \
  --prefill_load_sockets $PREFILL_LOAD_SOCKETS \
  --prefill_predictor_path ${SCRIPT_DIR}/prefill_pred_${PREFILL_INSTANCE_NUM}instance_${DATA_SOURCE}.yaml \
  --model_dir $MODEL_DIR 

# Launch midterm redirector
log_and_exec $SCRIPT_DIR/log.redirector python -m lightllm.server.midterm_redirector \
  --detokenization_socket ${CONTROL_HOST}:${DETOKENIZATION_TO_MID_START_PORT} \
  --prefill_query_url $DECODE_SCHEDULER_URL \
  --decode_instance_ids $DECODE_INSTANCES_IDS \
  --decode_load_sockets $DECODE_LOAD_SOCKETS \
  --decode_predictor_path ${SCRIPT_DIR}/decode_pred_${DECODE_INSTANCE_NUM}instance_${DATA_SOURCE}.yaml \
  --max_tokens $MAX_TOTAL_TOKEN_NUM \
  --decode_instance_sockets $DECODE_SCHE_SOCKETS 


rm $SCRIPT_DIR/log.backend*
# Launch MPI job
mpirun --allow-run-as-root -np $TOTAL_INSTANCE_NUM \
       -hostfile $SCRIPT_DIR/$HOSTFILE \
       bash $SCRIPT_DIR/pord.sh $CONFIG_FILE $PD_CONFIG_FILE


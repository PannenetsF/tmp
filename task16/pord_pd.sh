#!/bin/bash

source $1
DATA_SOURCE=$2

# PREFILL_INSTANCE_NUM=1
# DECODE_INSTANCE_NUM=3
# if not PREFILL_INSTANCE_NUM is not set, exit and print the usage; 
# if not DECODE_INSTANCE_NUM is not set, exit and print the usage; 
 
if [ -z "$PREFILL_INSTANCE_NUM" ]; then
  echo "PREFILL_INSTANCE_NUM is not set. Please set it to the number of prefill instances you want to run."
  exit 1
fi 
if [ -z "$DECODE_INSTANCE_NUM" ]; then
  echo "DECODE_INSTANCE_NUM is not set. Please set it to the number of decode instances you want to run."
  exit 1
fi

REMOTE_DIR="/data/fanyunqian/sch/distkv/lightllm"
export LIGHTLLM_LOG_LEVEL=debug
export PYTHONPATH=$PYTHONPATH:$REMOTE_DIR:viztracer/src/


rm log.*

NCCL_PORT=9999
NCCL_HOST=10.121.4.14

TP_PER_INSTANCE=1

PREFILL_HOSTS=("10.121.4.14")
PREFILL_IPS=("10.121.4.14")
DECODE_HOSTS=("10.121.4.14")
DECODE_IPS=("10.121.4.14")

CONTROL_HOST=$NCCL_HOST

DETOKENIZATION_FROM_ROUTER_START_PORT=11000
DETOKENIZATION_TO_HTTP_START_PORT=12000

TOTAL_INSTANCE_NUM=$((${#PREFILL_HOSTS[@]} * $PREFILL_INSTANCE_NUM + ${#DECODE_HOSTS[@]} * $DECODE_INSTANCE_NUM))

PREFILL_START_PORT=13000
DECODE_START_PORT=14000

PREFILL_LOAD_START_PORT=15000
DECODE_LOAD_START_PORT=16000

DECODE_SCHEDULER_SOCKET_START_PORT=17000
DECODE_SCHEDULER_CONTROL_PORT=18000
DECODE_SCHEDULER_URL="${CONTROL_HOST}:${DECODE_SCHEDULER_CONTROL_PORT}"
DETOKENIZATION_TO_MID_START_PORT=19000

MODEL_DIR="/data/models/Meta-Llama-3-8B/"
PARAM_CACHE='/data/fanyunqian/sch/param_cache/8b_tp1'

SCRIPT_DIR=$(dirname $0)

PIDS=()

MAX_REQ_INPUT_LEN=135000
MAX_REQ_TOTAL_LEN=140000
MAX_TOTAL_TOKEN_NUM=320000


# Function to check and sync directories
sync_directory() {
  local host=$1
  local working_dir=$(pwd)
  if [ "$host" == "$NCCL_HOST" ]; then
    return
  fi
  local remote_dir_exists=$(ssh $host "[ -d $working_dir ] && echo 'exists' || echo 'not exists'")

  if [ "$remote_dir_exists" == "not exists" ]; then
    echo "Directory $working_dir does not exist on $host. Copying from local..."
    scp -r $working_dir $host:$working_dir
  else
    echo "Directory $working_dir exists on $host. Syncing with rsync..."
    rsync -avz $working_dir/ $host:$working_dir/
  fi
}


close() {
  ps aux | grep api_server | awk '{print $2}' | xargs -n1 kill -KILL
  ps aux | grep frontend_server | awk '{print $2}' | xargs -n1 kill -KILL
  ps aux | grep midterm_redirector | awk '{print $2}' | xargs -n1 kill -KILL
  ps aux | grep backend_pord_server | awk '{print $2}' | xargs -n1 kill -KILL
  ps aux | grep lightllm_pord | awk '{print $2}' | xargs -n1 kill -KILL
  ps aux | grep spawn_main | awk '{print $2}' | xargs -n1 kill -KILL
}

close

# Function to kill all launched processes
cleanup() {
  echo "Cleaning up..."
  for PID in "${PIDS[@]}"; do
    echo "Killing process $PID"
    kill $PID
  done

  for host in "${PREFILL_HOSTS[@]}"; do
    if [ "$host" != "$NCCL_HOST" ]; then
      echo "Running cleanup on remote host $host"
      # ssh $host "ps aux | grep backend | awk '{print \$2}' | xargs -n1 kill -KILL"
      # ssh $host "ps aux | grep api_server | awk '{print \$2}' | xargs -n1 kill -KILL" 
      # ssh $host "ps aux | grep frontend | awk '{print \$2}' | xargs -n1 kill -KILL" 
      # ssh $host "ps aux | grep redirector | awk '{print \$2}' | xargs -n1 kill -KILL"
      ssh $host "ps aux | grep api_server | awk '{print \$2}' | xargs -n1 kill -KILL" 
      ssh $host "ps aux | grep frontend_server | awk '{print \$2}' | xargs -n1 kill -KILL"
      ssh $host "ps aux | grep midterm_redirector | awk '{print \$2}' | xargs -n1 kill -KILL"
      ssh $host "ps aux | grep backend_pord_server | awk '{print \$2}' | xargs -n1 kill -KILL"
      ssh $host "ps aux | grep lightllm_pord | awk '{print \$2}' | xargs -n1 kill -KILL"
      ssh $host "ps aux | grep spawn_main | awk '{print \$2}' | xargs -n1 kill -KILL"
    fi
  done

  for host in "${DECODE_HOSTS[@]}"; do
    if [ "$host" != "$NCCL_HOST" ]; then
      echo "Running cleanup on remote host $host"
      ssh $host "ps aux | grep api_server | awk '{print \$2}' | xargs -n1 kill -KILL" 
      ssh $host "ps aux | grep frontend_server | awk '{print \$2}' | xargs -n1 kill -KILL"
      ssh $host "ps aux | grep midterm_redirector | awk '{print \$2}' | xargs -n1 kill -KILL"
      ssh $host "ps aux | grep backend_pord_server | awk '{print \$2}' | xargs -n1 kill -KILL"
      ssh $host "ps aux | grep lightllm_pord | awk '{print \$2}' | xargs -n1 kill -KILL"
      ssh $host "ps aux | grep spawn_main | awk '{print \$2}' | xargs -n1 kill -KILL"
    fi
  done
}
cleanup

trap cleanup SIGINT SIGTERM


echo "cmds are" | tee log.commands
# Function to run pord server via SSH if the host is remote
run_remote() {
  local host=$1
  local cmd=$2
  if [ "$host" != "$NCCL_HOST" ]; then
    envset="export LIGHTLLM_LOG_LEVEL=debug; export PYTHONPATH=$PYTHONPATH:$REMOTE_DIR"
    cmd="cd $REMOTE_DIR; $envset; $cmd"
    echo "Running command on $host: $cmd" | tee -a log.commands
    ssh $host "$cmd"
  else
    # need to go to the remote directory to run the command, also set the exported env
    echo "Running command on $host: $cmd" | tee -a log.commands
    eval $cmd
  fi
}

# Sync directories for PREFILL_HOSTS and DECODE_HOSTS
for host in "${PREFILL_HOSTS[@]}"; do
  sync_directory $host
done

for host in "${DECODE_HOSTS[@]}"; do
  sync_directory $host
done

# share the nccl port to the remote
for host in "${PREFILL_HOSTS[@]}"; do
  if [ "$host" != "$NCCL_HOST" ]; then
    echo 
  fi
done

PREFILL_SOCKETS=$(for i in $(seq 0 $((${#PREFILL_HOSTS[@]} * $PREFILL_INSTANCE_NUM - 1))); do
  host=${PREFILL_HOSTS[$((i / $PREFILL_INSTANCE_NUM))]}
  local_port=$(($PREFILL_START_PORT + 20 * $i))
  echo -n "${PREFILL_IPS[$((i / $PREFILL_INSTANCE_NUM))]}:$local_port,"
done | sed 's/,$//')

PREFILL_LOAD_SOCKETS=$(for i in $(seq 0 $((${#PREFILL_HOSTS[@]} * $PREFILL_INSTANCE_NUM - 1))); do
  host=${PREFILL_HOSTS[$((i / $PREFILL_INSTANCE_NUM))]}
  local_port=$(($PREFILL_LOAD_START_PORT + 20 * $i))
  echo -n "${PREFILL_IPS[$((i / $PREFILL_INSTANCE_NUM))]}:$local_port,"
done | sed 's/,$//')

DECODE_LOAD_SOCKETS=$(for i in $(seq 0 $((${#DECODE_HOSTS[@]} * $DECODE_INSTANCE_NUM - 1))); do
  host=${DECODE_HOSTS[$((i / $DECODE_INSTANCE_NUM))]}
  local_port=$(($DECODE_LOAD_START_PORT + 20 * $i))
  echo -n "${DECODE_IPS[$((i / $DECODE_INSTANCE_NUM))]}:$local_port,"
done | sed 's/,$//')

PREFILL_DETOKENIZATION_SOCKETS=$(for i in $(seq 0 $((${#PREFILL_HOSTS[@]} * $PREFILL_INSTANCE_NUM - 1))); do
  host=${PREFILL_HOSTS[$((i / $PREFILL_INSTANCE_NUM))]}
  local_port=$(($DETOKENIZATION_FROM_ROUTER_START_PORT + 20 * $i))
  echo -n "${CONTROL_HOST}:$local_port,"
done | sed 's/,$//')

DECODE_DETOKENIZATION_FROM_ROUTER_SOCKETS=$(for i in $(seq 0 $((${#DECODE_HOSTS[@]} * $DECODE_INSTANCE_NUM - 1))); do
  host=${DECODE_HOSTS[$((i / $DECODE_INSTANCE_NUM))]}
  local_port=$(($DETOKENIZATION_FROM_ROUTER_START_PORT + 20 * $i + 20 * ${#PREFILL_HOSTS[@]} * $PREFILL_INSTANCE_NUM))
  echo -n "${CONTROL_HOST}:$local_port,"
done | sed 's/,$//')

DETOKENIZATION_FROM_ROUTER_SOCKETS=${PREFILL_DETOKENIZATION_SOCKETS},${DECODE_DETOKENIZATION_FROM_ROUTER_SOCKETS}

echo detokenization from router sockets "$DETOKENIZATION_FROM_ROUTER_SOCKETS" $DECODE_HOSTS $DECODE_INSTANCE_NUM

DECODE_SOCKETS=$(for i in $(seq 0 $((${#DECODE_HOSTS[@]} * $DECODE_INSTANCE_NUM - 1))); do
  host=${DECODE_HOSTS[$((i / $DECODE_INSTANCE_NUM))]}
  local_port=$(($DECODE_START_PORT + 20 * $i))
  echo -n "${DECODE_IPS[$((i / $DECODE_INSTANCE_NUM))]}:$local_port,"
done | sed 's/,$//')

DECODE_SCHE_SOCKETS=$(for i in $(seq 0 $((${#DECODE_HOSTS[@]} * $DECODE_INSTANCE_NUM - 1))); do
  host=${DECODE_HOSTS[$((i / $DECODE_INSTANCE_NUM))]}
  local_port=$(($DECODE_SCHEDULER_SOCKET_START_PORT + 20 * $i))
  echo -n "${DECODE_IPS[$((i / $DECODE_INSTANCE_NUM))]}:$local_port,"
done | sed 's/,$//')

echo prefill load sockets: $PREFILL_LOAD_SOCKETS
echo prefill sockets: $PREFILL_SOCKETS

DECODE_IDS=$(seq $((${#PREFILL_HOSTS[@]} * $PREFILL_INSTANCE_NUM)) $((${#PREFILL_HOSTS[@]} * $PREFILL_INSTANCE_NUM + ${#DECODE_HOSTS[@]} * $DECODE_INSTANCE_NUM - 1)) | tr '\n' ',' | sed 's/,$//')


python -m lightllm.server.frontend_server --host $CONTROL_HOST --port 9090 \
  --max_req_total_len $MAX_REQ_TOTAL_LEN --max_req_input_len $MAX_REQ_INPUT_LEN --max_total_token_num $MAX_TOTAL_TOKEN_NUM \
  --tokenizer_mode fast --nccl_ip $NCCL_HOST --nccl_port $NCCL_PORT \
  --trust_remote_code \
  --detokenization_recv_from_router_socket $DETOKENIZATION_FROM_ROUTER_SOCKETS \
  --detokenization_send_to_http_sockets ${CONTROL_HOST}:${DETOKENIZATION_TO_HTTP_START_PORT} \
  --prefill_sockets $PREFILL_SOCKETS \
  --detokenization_send_to_midterm_socket ${CONTROL_HOST}:${DETOKENIZATION_TO_MID_START_PORT} \
  --prefill_load_sockets $PREFILL_LOAD_SOCKETS \
  --prefill_predictor_path ${SCRIPT_DIR}/prefill_pred_${PREFILL_INSTANCE_NUM}instance_${DATA_SOURCE}.yaml \
  --model_dir $MODEL_DIR 2>&1 | tee log.frontend &
PIDS+=($!)

# separate by ,
python -m lightllm.server.midterm_redirector \
  --detokenization_socket ${CONTROL_HOST}:${DETOKENIZATION_TO_MID_START_PORT} \
  --prefill_query_url $DECODE_SCHEDULER_URL \
  --decode_instance_ids $DECODE_IDS \
  --decode_load_sockets $DECODE_LOAD_SOCKETS \
  --decode_predictor_path ${SCRIPT_DIR}/decode_pred_${DECODE_INSTANCE_NUM}instance_${DATA_SOURCE}.yaml \
  --max_tokens $MAX_TOTAL_TOKEN_NUM \
  --decode_instance_sockets $DECODE_SCHE_SOCKETS 2>&1 | tee log.redirector &
PIDS+=($!)

for i in $(seq 0 $((${#PREFILL_HOSTS[@]} * $PREFILL_INSTANCE_NUM - 1))); do
  host=${PREFILL_HOSTS[$((i / $PREFILL_INSTANCE_NUM))]}
  local_port=$(($PREFILL_START_PORT + 20 * $i))
  cmd="NCCL_SOCKET_IFNAME=bond0 python -m lightllm.server.backend_pord_server --model_dir $MODEL_DIR \
    --max_req_total_len $MAX_REQ_TOTAL_LEN --max_req_input_len $MAX_REQ_INPUT_LEN --max_total_token_num $MAX_TOTAL_TOKEN_NUM \
    --running_max_req_size  10 \
    --batch_max_tokens $(($MAX_REQ_TOTAL_LEN + 10)) \
    --parameter_cache $PARAM_CACHE \
    --host ${PREFILL_IPS[$((i / $PREFILL_INSTANCE_NUM))]} \
    --tp $TP_PER_INSTANCE \
    --nccl_ip $NCCL_HOST \
    --nccl_port $NCCL_PORT \
    --instance_id $i \
    --instance_num $TOTAL_INSTANCE_NUM \
    --router_socket ${PREFILL_IPS[$((i / $PREFILL_INSTANCE_NUM))]}:$local_port \
    --detokenization_socket ${CONTROL_HOST}:$(($DETOKENIZATION_FROM_ROUTER_START_PORT + 20 * $i)) \
    --dist_mode prefill \
    --local_instance_num $TOTAL_INSTANCE_NUM \
    --socket_server_addr_port ${PREFILL_IPS[$((i / $PREFILL_INSTANCE_NUM))]}:$(($PREFILL_LOAD_START_PORT + 20 * $i)) \
    --decode_scheduler_url $DECODE_SCHEDULER_URL 2>&1 | tee log.backend.prefill.$i"
  run_remote $host "$cmd" &
  PIDS+=($!)
done

for i in $(seq 0 $((${#DECODE_HOSTS[@]} * $DECODE_INSTANCE_NUM - 1))); do
  host=${DECODE_HOSTS[$((i / $DECODE_INSTANCE_NUM))]}
  local_port=$(($DECODE_START_PORT + 20 * $i))
  # cmd="NCCL_SOCKET_IFNAME=bond0 python -m lightllm.server.backend_pord_server --model_dir $MODEL_DIR \
  cmd="NCCL_SOCKET_IFNAME=bond0 python -m lightllm.server.backend_pord_server --model_dir $MODEL_DIR \
    --max_req_total_len $MAX_REQ_TOTAL_LEN --max_req_input_len $MAX_REQ_INPUT_LEN --max_total_token_num $MAX_TOTAL_TOKEN_NUM \
    --parameter_cache $PARAM_CACHE \
    --host ${DECODE_IPS[$((i / $DECODE_INSTANCE_NUM))]} \
    --tp $TP_PER_INSTANCE \
    --nccl_ip $NCCL_HOST \
    --nccl_port $NCCL_PORT \
    --instance_id $(($i + ${#PREFILL_HOSTS[@]} * $PREFILL_INSTANCE_NUM)) \
    --instance_num $TOTAL_INSTANCE_NUM \
    --router_socket ${DECODE_IPS[$((i / $DECODE_INSTANCE_NUM))]}:$local_port \
    --detokenization_socket ${CONTROL_HOST}:$(($DETOKENIZATION_FROM_ROUTER_START_PORT + 20 * $i + 20 * ${#PREFILL_HOSTS[@]} * $PREFILL_INSTANCE_NUM)) \
    --dist_mode decode \
    --local_instance_num $TOTAL_INSTANCE_NUM \
    --socket_server_addr_port ${DECODE_IPS[$((i / $DECODE_INSTANCE_NUM))]}:$(($DECODE_LOAD_START_PORT + 20 * $i)) \
    --decode_scheduler_socket ${DECODE_IPS[$((i / $DECODE_INSTANCE_NUM))]}:$(($DECODE_SCHEDULER_SOCKET_START_PORT + 20 * $i)) 2>&1 | tee log.backend.decode.$i"
  run_remote $host "$cmd" &
  PIDS+=($!)
done

(while true; do sleep 1; done) &
EMPTY_PID=$!
PIDS+=($EMPTY_PID)

wait $EMPTY_PID

cleanup
close
echo "All processes finished"


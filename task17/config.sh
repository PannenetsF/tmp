#!/bin/bash

# Model and data configuration
export MODEL_DIR="/data/basemodel/llama3.1/Meta-Llama-3.1-8B/"
export PARAM_CACHE="/data/fanyunqian/ela-1004/ela-1004param_cache/8b_tp1/"

# Request limits
export MAX_REQ_TOTAL_LEN=140000
export MAX_REQ_INPUT_LEN=135000
export MAX_TOTAL_TOKEN_NUM=320000


# Network configuration
export NCCL_HOST="10.119.22.36"
export NCCL_PORT=9999
export CONTROL_HOST="10.119.22.36"

# Instance configuration
export TP_PER_INSTANCE=1
export PREFILL_INSTANCE_NUM=8
export DECODE_INSTANCE_NUM=24

# Host configuration
export ALL_HOSTS=("app-vzucgzpq-848bb9b8b7-vhrtq" "app-vzucgzpq-848bb9b8b7-7nzhc" "app-vzucgzpq-848bb9b8b7-jf8q7" "app-vzucgzpq-848bb9b8b7-j7vdl")

# Host info
export ALL_IPS=("10.119.22.36" "10.119.22.19" "10.119.21.226" "10.119.21.211")

# Port configurations
export PREFILL_START_PORT=13000
export DECODE_START_PORT=16000
export PREFILL_LOAD_START_PORT=19000
export DECODE_LOAD_START_PORT=22000
export DECODE_SCHEDULER_SOCKET_START_PORT=25000
export DECODE_SCHEDULER_CONTROL_PORT=28000
export DETOKENIZATION_FROM_ROUTER_START_PORT=31000
export DETOKENIZATION_TO_HTTP_START_PORT=34000
export DETOKENIZATION_TO_MID_START_PORT=37000
# URLs 
export DECODE_SCHEDULER_URL="${CONTROL_HOST}:${DECODE_SCHEDULER_CONTROL_PORT}"
# Script directories
export SCRIPT_DIR=$(dirname $0)

# Python and CUDA configuration
export PYTHONPATH=$PYTHONPATH:/data/fanyunqian/ela-1004/ela-1004distkv/lightllm/:/data/fanyunqian/ela-1004/ela-1004distkv/lightllm/viztracer

# Logging
export LIGHTLLM_LOG_LEVEL=info



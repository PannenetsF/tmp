# echo all args
SCRIPT_DIR=$(dirname $0)
# Check if config file is provided
if [ "$#" -ne 4 ]; then
    echo "Usage: $0 <interval> <data_source> <rate_scale> <ip_host>"
    exit 1
fi
interval=$1
data=$2
rate=$3
ip_host=$4
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY

mkdir -p $SCRIPT_DIR/PD/

python evaluation/shared/benchmarks/benchmark_serving.py \
	--backend lightllm \
	--host $ip_host \
	--port 9090 \
	--dataset-name io \
	--dataset-path $SCRIPT_DIR/../shared/data/$data.txt \
	--random-output-len 200 \
	--random-input-len 500 \
	--model llama2-7b \
	--tokenizer /data/basemodel/llama3.1/Meta-Llama-3.1-8B/ \
	--num-prompts 2000 \
	--endpoint /generate_stream \
	--dyna_rate_file $SCRIPT_DIR/../shared/data/schat_freq.txt \
	--dyna_rate_interval $interval \
  --request_scale_rate $rate 2>&1

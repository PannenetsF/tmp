# echo all args
SCRIPT_DIR=$(dirname $0)
# fisrt args 
interval=$1
data=$2
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY

mkdir -p $SCRIPT_DIR/PD/

python evaluation/shared/benchmarks/benchmark_serving.py \
	--backend lightllm \
	--host 10.121.4.14 \
	--port 9090 \
	--dataset-name io \
	--dataset-path $SCRIPT_DIR/../shared/data/$data.txt \
	--random-output-len 200 \
	--random-input-len 500 \
	--model llama2-7b \
	--tokenizer /data/models/Meta-Llama-3-8B/ \
	--num-prompts 2000 \
	--endpoint /generate_stream \
	--dyna_rate_file $SCRIPT_DIR/../shared/data/schat_freq.txt \
	--dyna_rate_interval $interval 

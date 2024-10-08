#! /bin/bash

SCRIPT_DIR=$(dirname $0)
BENCH_SCRIPT=$SCRIPT_DIR/../shared/benchmark_fix_rate.py

export PYTHONPATH=evaluation/shared/benchmarks/

# rm $SCRIPT_DIR/decode_hi*
# rm $SCRIPT_DIR/prefill_hi*
# rm $SCRIPT_DIR/log.*

# exit

# xm_real_data p2d1 p2d6 p4d4 p6d2 

# schat p1d3 p2d6 p4d4 p6d2 

# docqq p1d3 p2d6 p4d4 p6d2 

it=0.1

cnt=0
total=15


cfgs=(
    "p1d2 xm_real_data"
    "p1d2 schat"
    "p1d3 schat"
    "p2d2 docqa"
    "p2d3 docqa"
    "p3d3 docqa"
)

for cfg in "${cfgs[@]}"; do
    pd=$(echo $cfg | cut -d' ' -f1)
    data_name=$(echo $cfg | cut -d' ' -f2)
    fn=$SCRIPT_DIR/log.$pd.$it.$data_name
    if [ -f $fn ]; then
        if grep -q "Serving Benchmark Result" $fn; then
            echo "Skip $pd $data_name"
            cnt=$((cnt+1))
            continue
        fi
    fi
    echo ======================================
    echo "Running $pd $data_name" $cnt / $total
    echo ======================================
    bash $SCRIPT_DIR/pord_pd.sh $SCRIPT_DIR/test_7b_pord_$pd.sh $data_name > /dev/null &
    PID=$!
    bash $SCRIPT_DIR/bench_serve.sh $it $data_name | tee $fn
    kill -SIGINT $PID
    kill -SIGTERM $PID
    echo "Killed the test script"
    mv $SCRIPT_DIR/decode_history.json $SCRIPT_DIR/decode_history.$pd.$it.$data_name.json
    mv $SCRIPT_DIR/prefill_history.json $SCRIPT_DIR/prefill_history.$pd.$it.$data_name.json
    cnt=$((cnt+1))
done


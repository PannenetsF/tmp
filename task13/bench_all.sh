#! /bin/bash

SCRIPT_DIR=$(dirname $0)
BENCH_SCRIPT=$SCRIPT_DIR/../shared/benchmark_fix_rate.py

export PYTHONPATH=evaluation/shared/benchmarks/

it=0.1
rate=5

bash $SCRIPT_DIR/kill.sh $SCRIPT_DIR/config.sh 
source $SCRIPT_DIR/config.sh 

for pd in p16d16 p8d24 p24d8; do
    for data_name in xm_real_data schat docqa ; do
        fn=$SCRIPT_DIR/log.$pd.$it.$data_name
        if [ -f $fn ]; then
            if grep -q "Serving Benchmark Result" $fn; then
                echo "Skip $pd $data_name"
                cnt=$((cnt+1))
                continue
            fi
        fi
        echo "Running $pd $data_name"
        bash $SCRIPT_DIR/pord-mpi.sh $SCRIPT_DIR/config.sh $SCRIPT_DIR/${pd}.sh $data_name > /dev/null &
        PID=$!
        bash $SCRIPT_DIR/bench_serve.sh $it $data_name $rate $CONTROL_HOST 2>&1 | tee $fn
        bash $SCRIPT_DIR/kill.sh $SCRIPT_DIR/config.sh 
        kill -SIGINT $PID
        kill -SIGTERM $PID
        mv $SCRIPT_DIR/decode_history.json $SCRIPT_DIR/decode_history.$pd.$it.$data_name.json
        mv $SCRIPT_DIR/prefill_history.json $SCRIPT_DIR/prefill_history.$pd.$it.$data_name.json
    done
done

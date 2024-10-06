
PREFILL_INSTANCE_NUM_PER_NODE=6
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
_get_mode_idx() {
    local idx=$1
    idx=$((idx % 8))
    local node_rank=$((idx / 8))  # 当前是第几个节点
    local prefill_per_node=$PREFILL_INSTANCE_NUM_PER_NODE
    
    if [ $idx -lt $PREFILL_INSTANCE_NUM_PER_NODE ]; then
        # prefill 情况下的 real_idx
        real_idx=$((node_rank * prefill_per_node + idx % 8))
        echo $real_idx
    else
        # decode 情况下的 real_idx
        real_idx=$((node_rank * (8 - prefill_per_node) + idx % 8 - prefill_per_node))
        echo $real_idx
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


for i in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16
do 
  a=$(get_mode_idx $i)
  echo $i $a
done

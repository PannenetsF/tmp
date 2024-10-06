#!/bin/bash

# Check if config file is provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <config_file>"
    exit 1
fi

# Load environment variables from the config file
source $1

# Function to kill processes on a remote host
kill_remote_processes() {
    local host=$1
    ssh $host "ps aux | grep 'lightllm.server.backend_pord_server' | awk '{print \$2}' | xargs -n1 kill -KILL" 
    ssh $host "ps aux | grep 'lightllm_pord' | awk '{print \$2}' | xargs -n1 kill -KILL" 
    ssh $host "ps aux | grep 'lightllm.server.frontend_server' | awk '{print \$2}' | xargs -n1 kill -KILL" 
    ssh $host "ps aux | grep 'lightllm.server.midterm_redirector' | awk '{print \$2}' | xargs -n1 kill -KILL" 
    ssh $host "ps aux | grep 'mpirun' | awk '{print \$2}' | xargs -n1 kill -KILL" 
    ssh $host "ps aux | grep 'spawn_main' | awk '{print \$2}' | xargs -n1 kill -KILL" 
    ssh $host "ps aux | grep 'multiprocessing' | awk '{print \$2}' | xargs -n1 kill -KILL" 
}

# Kill processes on the control node
echo "Killing processes on control node ${CONTROL_HOST}..."
kill -KILL $(pgrep -f 'python -m lightllm.server.backend_pord_server')
kill -KILL $(pgrep -f 'lightllm_pord')
kill -KILL $(pgrep -f 'python -m lightllm.server.frontend_server')
kill -KILL $(pgrep -f 'python -m lightllm.server.midterm_redirector')
kill -KILL $(pgrep -f 'mpirun')
kill -KILL $(pgrep -f 'spawn_main')
kill -KILL $(pgrep -f 'multiprocessing')
# Kill processes on all other nodes
for host in "${ALL_IPS[@]}"; do
    if [ "$host" != "$CONTROL_HOST" ]; then
        echo "Killing processes on $host..."
        kill_remote_processes $host
    fi
done
wait

echo "All processes have been terminated."

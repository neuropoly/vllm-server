#!/usr/bin/env bash
# Stop the vLLM server and the PDF proxy in front of it, close their tmux sessions, and make sure no
# vLLM process still holds the GPU. Refuses while requests are running or waiting (someone is using
# the model right now), unless --force. An agent idle between two questions has no request running.
# Usage: bash stop_vllm.sh [--force]
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/vllm.env"
source "$HERE/tmux_lib.sh"
force=0; [ "${1:-}" = --force ] && force=1

# Requests running + waiting, from vLLM's /metrics (no key needed). Empty if vLLM doesn't answer.
# vLLM listens on VLLM_PORT behind the PDF proxy, on PORT without it: try both.
in_flight() {
    local p
    for p in "$VLLM_PORT" "$PORT"; do
        curl -sf --max-time 3 "http://127.0.0.1:$p/metrics" 2>/dev/null \
            | awk '/^vllm:num_requests_(running|waiting)\{/ {s += $2; n++} END {if (n) printf "%d", s}' \
            | grep . && return
    done
}
n=$(in_flight)
if [ "$force" = 0 ] && [ "${n:-0}" -gt 0 ]; then
    echo "Not stopped: $n request(s) running or waiting, someone is using the model right now."
    echo "See: bash $HERE/status.sh   Stop anyway: bash $HERE/stop_vllm.sh --force"
    exit 1
fi

stop_session doc-proxy 'doc_proxy\.py'
stop_session vllm 'vllm serve|VLLM::EngineCore'
echo "vLLM stopped. GPU $GPU:"
nvidia-smi -i "$GPU" --query-gpu=index,memory.used,memory.total --format=csv,noheader

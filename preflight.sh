#!/usr/bin/env bash
# Read-only check of tassan before installing or starting anything. Changes nothing.
# Usage: bash preflight.sh
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/vllm.env"
ok()   { printf '  [ok]   %s\n' "$*"; }
warn() { printf '  [WARN] %s\n' "$*"; }

echo "== tools"
for t in tmux git curl python3 nvidia-smi; do
    command -v "$t" >/dev/null && ok "$t" || warn "$t missing"
done
# tmux opens a login shell, so that is where set_slot must exist.
slot=${SLOT_CMD%% *}
if [ -z "$slot" ]; then echo "  [--]   no SLOT_CMD in vllm.env"
elif bash -lic "type $slot" >/dev/null 2>&1; then ok "$slot available in a login shell (vllm.env runs: $SLOT_CMD)"
else warn "$slot not found in a login shell: servers would refuse to start. Fix SLOT_CMD in vllm.env"; fi
[ -x "$VLLM_ROOT/vllm-venv/bin/vllm" ] && ok "vLLM installed" || echo "  [--]   vLLM not installed yet (setup_vllm.sh)"
[ -s "$KEY_FILE" ] && ok "lab key ($KEY_FILE)" || warn "no lab key at $KEY_FILE (deployed separately): servers would refuse to start"

echo "== GPUs (card $GPU is ours)"
nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu --format=csv,noheader | sed 's/^/  /'
others=$(nvidia-smi -i "$GPU" --query-compute-apps=pid,process_name,used_memory --format=csv,noheader)
if [ -n "$others" ]; then warn "processes on card $GPU:"; echo "$others" | sed 's/^/    /'; else ok "card $GPU idle"; fi

echo "== disk"
df -h "$VLLM_ROOT" 2>/dev/null | tail -1 | sed 's/^/  /' || df -h "$(dirname "$VLLM_ROOT")" | tail -1 | sed 's/^/  /'
du -sh "$VLLM_ROOT" 2>/dev/null | sed 's/^/  VLLM_ROOT: /'
echo "  needs ~15 GB for the venvs + ~30 GB per model (Qwen3.6-27B FP8), ~45 GB for the 80B coder"

echo "== network"
curl -sfI https://huggingface.co -o /dev/null --max-time 10 && ok "huggingface.co reachable" || warn "huggingface.co not reachable"
curl -sfI https://pypi.org -o /dev/null --max-time 10 && ok "pypi.org reachable" || warn "pypi.org not reachable"
curl -sfI https://github.com -o /dev/null --max-time 10 && ok "github.com reachable (SearXNG, uv)" || warn "github.com not reachable"

echo "== servers"
tmux ls 2>/dev/null | sed 's/^/  tmux: /' || echo "  no tmux sessions"
left=$(pgrep -a -u "$USER" -f 'vllm serve|VLLM::EngineCore|doc_proxy\.py|searx\.webapp|search_mcp\.py')
[ -n "$left" ] && { warn "server processes of ours still running (stop_vllm.sh / stop_search.sh clean them up):"; echo "$left" | sed 's/^/    /'; }
ss -ltn 2>/dev/null | grep -E ':(8000|8010|8002|8888) ' | sed 's/^/  listening: /' || true

# vllm-server

The NeuroPoly lab's self-hosted coding model on tassan: a [vLLM](https://github.com/vllm-project/vllm) server (GPU 1), a PDF proxy in front of it, and a web search service for the agents. Lab members use it from Claude Code or OpenCode through an SSH tunnel; the client side and the user guide live in [benchmark-local-llm](https://github.com/neuropoly/benchmark-local-llm/blob/main/lab_server/USER_GUIDE.md).

## Layout

This repo is cloned into `/opt/vllm/vllm-server`. Everything the scripts generate goes next to it, under `VLLM_ROOT` (`/opt/vllm`, set in `vllm.env`), never inside the checkout:

```
/opt/vllm/
  vllm-server/    this repo (vllm.env is the only file to edit)
  vllm.key        the lab API key, deployed separately (never in git)
  vllm-venv/      vLLM + its own CUDA compiler            (setup_vllm.sh)
  proxy-venv/     the PDF proxy                            (setup_vllm.sh)
  hf/             model weights, ~30 GB per model          (setup_vllm.sh, switch_model.sh)
  searxng/        SearXNG, its own git clone               (setup_search.sh)
  search/         SearXNG and MCP venvs, settings.yml      (setup_search.sh; settings.yml holds a generated secret_key)
  bin/            uv
  .cache/         FlashInfer kernels, vLLM and uv caches
  logs/           vllm.log, doc-proxy.log, searxng.log, search-mcp.log
  model.env       the model chosen with switch_model.sh, if any
```

To run a test copy elsewhere, set `VLLM_ROOT` (and the key with it) in the environment: `VLLM_ROOT=~/vllm-test bash setup_vllm.sh`.

## Ports

All bound to `127.0.0.1` on tassan; clients reach 8000 and 8002 through their SSH tunnel.

| port | what |
|---|---|
| 8000 (`PORT`) | the PDF proxy (`doc_proxy.py`), what clients talk to |
| 8010 (`VLLM_PORT`) | vLLM itself, behind the proxy (on 8000 directly if `DOC_PROXY=0`) |
| 8002 (`SEARCH_MCP_PORT`) | the web search MCP server (`search_mcp.py`) |
| 8888 (`SEARXNG_PORT`) | SearXNG, only the MCP server queries it |

## First deployment

Needs: `tmux`, `git`, `curl`, `python3`, `nvidia-smi`, `set_slot` (lab rule: the servers run inside `set_slot 1`), outbound internet (PyPI, Hugging Face, GitHub, and the search engines), and the key at `/opt/vllm/vllm.key`.

```bash
bash preflight.sh       # read-only check: tools, set_slot, card free, disk, network, key
bash setup_vllm.sh      # uv, vLLM (pinned in vllm.env), PDF proxy venv, model weights
bash setup_search.sh    # SearXNG + the search MCP server
bash serve_vllm.sh      # start; the first start compiles GPU kernels (15+ min), later ones take a few minutes
```

The setup scripts are safe to run again (they update and keep what is there). They never create the key.

## Day to day

```bash
bash status.sh                     # up or down, GPU memory, requests running/waiting, proxy, search
bash serve_vllm.sh                 # start vLLM + the PDF proxy (and the search, if installed); returns once it answers
bash stop_vllm.sh                  # stop vLLM + the PDF proxy, free GPU 1; refuses while requests are running
bash stop_vllm.sh --force          # stop anyway
bash serve_search.sh               # start the web search alone (serve_vllm.sh starts it too)
bash stop_search.sh                # stop the web search (stop_vllm.sh leaves it running)
bash switch_model.sh               # list the models (models.conf): which is set, running, downloaded
bash switch_model.sh <name>        # download if needed, restart vLLM on it (add --force if requests are running)
bash switch_model.sh <name> --no-start   # only record the choice
bash switch_model.sh default       # back to the model in vllm.env
tail -f /opt/vllm/logs/vllm.log    # also doc-proxy.log, searxng.log, search-mcp.log
tmux attach -t vllm                # watch the server (Ctrl+B then D to leave)
```

Each server runs in its own tmux session (`vllm`, `doc-proxy`, `searxng`, `search-mcp`), started inside `set_slot`, so it survives the SSH session that started it. Nothing restarts it after a reboot.

To check the PDF proxy end to end: `/opt/vllm/proxy-venv/bin/python check_pdf.py paper.pdf "What does Figure 1 show?"`.

## Settings

All in `vllm.env`: the card (`GPU=1`), ports, context length, GPU memory share, the pinned vLLM version, and the default model. Models to switch between are listed in `models.conf`.

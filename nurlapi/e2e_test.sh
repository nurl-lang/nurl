#!/usr/bin/env bash
# ============================================================
#  nurlapi/e2e_test.sh — run the end-to-end test harness against
#  a running nurlapi container (default: http://127.0.0.1:8000).
#
#  Usage:
#    ./nurlapi/e2e_test.sh               # full run
#    ./nurlapi/e2e_test.sh --quick       # skip the 'nurl_build_native' check
#    ./nurlapi/e2e_test.sh --base URL    # custom base URL
#
#  The harness drives both the REST surface (/health, /mcp-info,
#  /download, OAuth stubs) and the JSON-RPC MCP surface at POST /mcp
#  (initialize, tools/list, tools/call, resources/*, prompts/*, batches,
#  notifications, malformed input, traversal guards, session-id echo).
#  Stdlib-only Python — no extra deps.
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/e2e_test.py" "$@"

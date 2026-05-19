#!/usr/bin/env bash
# ============================================================
#  mcp_spec_drift_check.sh — verify NURL's pinned MCP protocol
#  revision matches the spec site's "current".
#
#  Fetches https://modelcontextprotocol.io/specification/versioning,
#  extracts the current revision string (YYYY-MM-DD), and compares
#  it to the value returned by stdlib/ext/mcp.nu's
#  mcp_protocol_version. Non-zero exit on drift.
#
#  MCP revisions only bump on backwards-incompatible changes (per
#  the spec's own versioning page), so drift = "the spec moved
#  underneath us and we should review what changed before claiming
#  conformance".
#
#  Usage:
#     bash tools/mcp_spec_drift_check.sh
#
#  Run periodically (e.g. weekly via cron, or as a CI step). Useful
#  reference run: paste the latest changelog URL into the prompt
#  when reviewing what changed.
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MCP_FILE="$ROOT_DIR/stdlib/ext/mcp.nu"

if [[ ! -f "$MCP_FILE" ]]; then
    echo "ERROR: $MCP_FILE not found — run from repo root" >&2
    exit 2
fi

# Parse NURL-side pinned version.
# mcp.nu encodes it as:
#     @ mcp_protocol_version → s {
#         ...
#         ^ `2025-11-25`
#     }
# Pick the `^`-return line specifically — the function body may also
# contain a "(as of YYYY-MM-DD; ...)" comment that we must NOT match.
PINNED=$(awk '
    /^@ mcp_protocol_version → s \{$/ { in_fn = 1; next }
    in_fn && /^\}$/                  { exit }
    in_fn && /^[[:space:]]*\^/       { print }
' "$MCP_FILE" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -n1)

if [[ -z "$PINNED" ]]; then
    echo "ERROR: could not extract pinned version from $MCP_FILE" >&2
    exit 2
fi

# Fetch the spec site's versioning page.
SPEC_URL="https://modelcontextprotocol.io/specification/versioning"
if ! command -v curl >/dev/null 2>&1; then
    echo "ERROR: curl required" >&2
    exit 2
fi

# 5s connect + 15s total — fail fast on a hung mirror.
SPEC_HTML="$(curl --max-time 15 --connect-timeout 5 -sSL "$SPEC_URL" 2>/dev/null || true)"
if [[ -z "$SPEC_HTML" ]]; then
    echo "ERROR: could not fetch $SPEC_URL" >&2
    echo "(network down? proxy issue? rerun later.)" >&2
    exit 3
fi

# Page says: "The **current** protocol version is [**YYYY-MM-DD**]..."
# Be lenient: accept either rendered markdown ("[**X**]") or HTML.
CURRENT=$(echo "$SPEC_HTML" \
    | grep -oE 'current[^0-9]{1,80}[0-9]{4}-[0-9]{2}-[0-9]{2}' \
    | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' \
    | head -n1)

if [[ -z "$CURRENT" ]]; then
    echo "ERROR: could not parse current version from $SPEC_URL" >&2
    echo "(spec site layout may have changed — update this script)" >&2
    exit 3
fi

echo "NURL pinned : $PINNED"
echo "Spec current: $CURRENT"

if [[ "$PINNED" == "$CURRENT" ]]; then
    echo "OK: NURL is up-to-date with the current MCP spec revision."
    exit 0
fi

# Drift detected — emit a hint at the changelog URL.
echo
echo "DRIFT: NURL pins '$PINNED' but the spec current is '$CURRENT'."
echo "Review the changelog for breaking changes:"
echo "  https://modelcontextprotocol.io/specification/$CURRENT/changelog"
echo
echo "To re-pin, edit stdlib/ext/mcp.nu's mcp_protocol_version helper."
exit 1

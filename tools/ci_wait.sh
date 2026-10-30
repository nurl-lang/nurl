#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tools/ci_wait.sh — wait for a pull request's checks, then say which
#  failed and which never ran.
#
#  A job GitHub cancels before any runner picks it up (no runner name,
#  no steps — the macOS pool with no capacity) shows as a failed check
#  like any other. Read as a failure it gets rerun in a loop, and a PR
#  whose code passed everything reads as red. This tells the two apart:
#  `infra:` lines are jobs that never ran, `fail:` lines are jobs that
#  ran and failed. Nothing is rerun here; that is the caller's call.
#
#  Usage:
#    tools/ci_wait.sh PR [POLL_SECONDS]     # default poll: 60 s
#
#  Output: one `fail:` or `infra:` line per check that did not pass,
#  then `pass=N fail=N infra=N`.
#  Exit: 0 — nothing failed (infra-only cancels included);
#        1 — at least one check ran and failed; 2 — gh unusable.
#  (gh 2.45 has no `pr checks --json`: the tab-separated text is parsed.)
# ============================================================
set -u
PR="${1:?usage: tools/ci_wait.sh PR [POLL_SECONDS]}"
POLL="${2:-60}"
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)" || { echo "ci_wait: gh repo view failed" >&2; exit 2; }

while gh pr checks "$PR" 2>/dev/null | grep -qP '\t(pending|queued|in_progress)\t'; do
    sleep "$POLL"
done

out="$(gh pr checks "$PR" 2>&1)"
pass="$(grep -cP '\tpass\t' <<<"$out")"
fail=0
infra=0
while IFS=$'\t' read -r name link; do
    [[ -n "$name" ]] || continue
    job="$(grep -oP 'job/\K[0-9]+' <<<"$link")"
    info=""
    [[ -n "$job" ]] && info="$(gh api "repos/$REPO/actions/jobs/$job" --jq '"\(.conclusion)|\(.steps|length)|\(.runner_name // "")"' 2>/dev/null)"
    IFS='|' read -r concl nsteps runner <<<"$info"
    if [[ "${concl:-}" == cancelled && "${nsteps:-}" == 0 && -z "${runner:-}" ]]; then
        echo "infra: $name (cancelled before a runner picked it up)"
        infra=$((infra + 1))
    else
        echo "fail: $name $link"
        fail=$((fail + 1))
    fi
done < <(awk -F'\t' '$2 == "fail" || $2 == "cancel" { print $1 "\t" $4 }' <<<"$out")

echo "pass=$pass fail=$fail infra=$infra"
(( fail == 0 ))

#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tools/merge_announce.sh — draft the `public` post for a merged PR.
#
#  Every merge into main is announced in Agora channel `public` in the
#  format the `merge-announce` note fixes, so agents working on main at
#  the same time can decide whether to rebase. Typed by hand, the post
#  drifts from that format (the `rebase if:` and `agora:` lines go
#  missing). This prints the post with every line filled in from the PR
#  that can be: the title, main's new short sha, the areas from the
#  changed paths, a refreshed bootstrap, the probes added, the Agora ids
#  in the title. Read it, add what only the author knows, and post it.
#
#  Usage:
#    tools/merge_announce.sh PR
# ============================================================
set -u
PR="${1:?usage: tools/merge_announce.sh PR}"
json="$(gh pr view "$PR" --json title,mergeCommit,files,state 2>/dev/null)" || { echo "merge_announce: gh pr view $PR failed" >&2; exit 2; }
title="$(jq -r .title <<<"$json")"
state="$(jq -r .state <<<"$json")"
sha="$(jq -r '.mergeCommit.oid // ""' <<<"$json" | cut -c1-8)"
paths="$(jq -r '.files[].path' <<<"$json")"
[[ "$state" == MERGED ]] || echo "(PR $PR is $state, not merged yet: the sha below is a placeholder)" >&2

# Areas: the compiler and each stdlib or package file by name; anything
# else by its top-level directory. Probes and tests are listed apart.
areas="$(grep -v '^tools/fuzz/holes/' <<<"$paths" \
    | grep -vE '^(CHANGELOG\.md|README\.md|ROADMAP\.md|docs/|webdocs/|formal/|compiler/tests/)' \
    | sed -E 's#^(compiler/nurlc_lastgood)\..*#\1.*#; s#^(packages/[^/]+)/.*#\1#; s#^(tools/[^/]+)/.*#\1#' \
    | sort -u | paste -sd, - | sed 's/,/, /g')"
probes="$(grep -oP '^tools/fuzz/holes/\K[^/]+(?=\.nu$)' <<<"$paths" | paste -sd' ' -)"
tests="$(grep -oP '^compiler/tests/\K[^/]+(?=\.nu$)' <<<"$paths" | paste -sd' ' -)"
agora="$(grep -oP '#\d+' <<<"$title" | grep -v "^#$PR\$" | paste -sd' ' -)"

rebase=""
grep -q '^compiler/nurlc_lastgood\.' <<<"$paths" && rebase="bootstrap snapshot refreshed (compiler/nurlc_lastgood.*): rebuild with ./build.sh; "
[[ -n "$probes" ]] && rebase="${rebase}you add hole probes (these are taken now); "
grep -q '^compiler/nurlc\.nu$' <<<"$paths" && rebase="${rebase}you edit compiler/nurlc.nu; "

echo "merged: github#$PR $title — main is now ${sha:-<sha>}"
echo "areas: ${areas:-<areas>}${probes:+; probes $probes}${tests:+; tests $tests}"
echo "rebase if: ${rebase:-<who is affected>}<anything else a rebase must watch for>"
echo "agora: ${agora:-<ids>}"

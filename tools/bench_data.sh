#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# tools/bench_data.sh — the measured numbers live on the `bench-data` branch.
#
#   tools/bench_data.sh publish MESSAGE PATH...
#       Commit this checkout's PATHs (files or directories, at the same
#       paths) onto the tip of bench-data and push. Another publisher can
#       push in between: the copy is replayed onto the new tip, up to five
#       times. With BENCH_DATA_RENDER set, that command runs inside the
#       bench-data tree after each copy, before the commit (tls-bench
#       re-renders its index from every family's recorded runs there).
#   tools/bench_data.sh fetch [--if-missing] PATH...
#       Write bench-data's PATHs into this checkout. --if-missing skips a
#       PATH that is already there (a local run's own numbers).
#   tools/bench_data.sh url PATH
#       The page that shows PATH's latest numbers on GitHub.
#
# Why a branch of its own (Agora #290): the benchmark and fuzz workflows
# used to push their reports straight to main, about a dozen commits a day.
# The merge queue tests every group on top of main, so each such push made
# it rebuild every group in flight and run its whole CI again; release
# v0.83.0's group ran three times, once for a bench commit. Numbers are not
# code: nothing on main is built from them, every report names its run and
# date, and their readers (nurl-lang.org's build, the links in the docs)
# read them from here. main moves only through the queue.
set -euo pipefail

BR="${BENCH_DATA_BRANCH:-bench-data}"
REMOTE="${BENCH_DATA_REMOTE:-origin}"
ROOT="$(git rev-parse --show-toplevel)"
REPO_URL="${BENCH_DATA_REPO_URL:-https://github.com/nurl-lang/nurl}"

die(){ printf 'bench_data.sh: %s\n' "$*" >&2; exit 1; }

fetch_tip() {
  git -C "$ROOT" fetch -q --depth=1 "$REMOTE" "+refs/heads/$BR:refs/remotes/$REMOTE/$BR" 2>/dev/null
}

cmd_fetch() {
  local if_missing=0
  [ "${1:-}" = --if-missing ] && { if_missing=1; shift; }
  [ $# -gt 0 ] || die "fetch: name at least one path"
  fetch_tip || die "fetch: no '$BR' branch on $REMOTE"
  local p
  for p in "$@"; do
    if [ "$if_missing" = 1 ] && [ -e "$ROOT/$p" ]; then continue; fi
    git -C "$ROOT" cat-file -e "$REMOTE/$BR:$p" 2>/dev/null || die "fetch: '$p' is not on $BR"
    # archive keeps a directory whole; the tar stream lands at the same path.
    git -C "$ROOT" archive --format=tar "$REMOTE/$BR" -- "$p" | tar -x -C "$ROOT"
  done
}

cmd_publish() {
  [ $# -ge 2 ] || die "publish: MESSAGE PATH..."
  local msg="$1"; shift
  local p
  for p in "$@"; do [ -e "$ROOT/$p" ] || die "publish: '$p' does not exist in this checkout"; done
  local wt; wt="$(mktemp -d)"
  trap 'git -C "$ROOT" worktree remove --force "$wt" >/dev/null 2>&1 || true; rm -rf "$wt"' RETURN
  local attempt
  for attempt in 1 2 3 4 5; do
    git -C "$ROOT" worktree remove --force "$wt" >/dev/null 2>&1 || true
    rm -rf "$wt"
    if fetch_tip; then
      git -C "$ROOT" worktree add -q --detach "$wt" "$REMOTE/$BR"
    else
      # The first publish: an orphan branch that holds numbers and nothing else.
      git -C "$ROOT" worktree add -q --detach "$wt" HEAD
      git -C "$wt" checkout -q --orphan "$BR"
      git -C "$wt" rm -rq --cached . >/dev/null
      find "$wt" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
    fi
    for p in "$@"; do
      mkdir -p "$wt/$(dirname "$p")"
      if [ -d "$ROOT/$p" ]; then
        mkdir -p "$wt/$p"; cp -R "$ROOT/$p/." "$wt/$p/"
      else
        cp "$ROOT/$p" "$wt/$p"
      fi
    done
    if [ -n "${BENCH_DATA_RENDER:-}" ]; then
      ( cd "$wt" && bash -c "$BENCH_DATA_RENDER" ) || die "publish: BENCH_DATA_RENDER failed"
    fi
    git -C "$wt" add -A .
    if git -C "$wt" diff --cached --quiet; then
      echo "bench_data.sh: $BR already carries these numbers — nothing to publish."
      return 0
    fi
    git -C "$wt" -c user.name="${GIT_AUTHOR_NAME:-github-actions[bot]}" \
                 -c user.email="${GIT_AUTHOR_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}" \
                 commit -q -m "$msg"
    if git -C "$wt" push -q "$REMOTE" "HEAD:refs/heads/$BR"; then
      echo "bench_data.sh: published to $BR: $(git -C "$wt" rev-parse --short HEAD) $msg"
      return 0
    fi
    echo "bench_data.sh: push refused (attempt $attempt) — replaying onto the new tip"
  done
  die "publish: could not push to $BR after 5 attempts"
}

cmd_url() {
  [ $# -eq 1 ] || die "url: PATH"
  printf '%s/blob/%s/%s\n' "$REPO_URL" "$BR" "$1"
}

case "${1:-}" in
  publish) shift; cmd_publish "$@" ;;
  fetch)   shift; cmd_fetch "$@" ;;
  url)     shift; cmd_url "$@" ;;
  *) die "usage: bench_data.sh publish MESSAGE PATH... | fetch [--if-missing] PATH... | url PATH" ;;
esac

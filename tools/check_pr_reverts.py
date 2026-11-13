#!/usr/bin/env python3
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
"""A pull request must not silently undo a commit that is already on main.

github#1746 was a proof-only change that reverted github#1741 in full: the
compiler change, its two tests and their goldens, its changelog fragments
and its hole probes. It had been squashed with

    git reset --soft origin/main && git commit

on a branch that was not rebased onto that origin/main, so the commit's tree
was older than its parent. CI was green, because the tests that would have
failed were deleted with the code they tested, and the merge queue landed it
(Agora #652).

What this checks. Let M be the merge-base of main and the head H, and take
main's last N first-parent commits up to M. Each path one of them touched has
a timeline of blob ids on main: v0 before the window's first touch, v1 … vk
after each commit c1 … ck that touched it. A path the head changes is placed
on its timeline:

  * H's blob is vj for some j < k (the latest such): commits c(j+1) … ck are
    ROLLED BACK on that path, and c1 … cj are kept. "No file" is a blob too,
    so a file a commit added and the head deletes is rolled back, and so is a
    file a commit deleted and the head brings back unchanged.
  * H's blob is none of them: the head gave the path content of its own. That
    counts for neither side.

A path the head does not change, or renames with its content untouched, is
kept as main has it.

A commit is UNDONE when at least one of its paths is rolled back and none is
kept. A stale squash undoes every commit of main it skipped: whatever the
author did not edit goes back to the old base. A fix that restores one golden
to what it said before a regression keeps the rest of the commit that
changed it, and passes.

Two kinds of file are made to be deleted, and such a deletion is no
evidence: an open-hole note tools/fuzz/holes/open/t<N>.md in the change that
closes the hole (its pull request or a commit message names `#N`), and a
changelog fragment in a release fold (a change that also edits CHANGELOG.md).
A note deleted by a change that never mentions its task is a note lost.

Everything is compared by blob id. There is no similarity threshold and no
text heuristic, so a verdict is a fact about the two trees.

An intended revert says so: a line

    reverts: <sha or #PR>[, <sha or #PR> …]

in the pull request body or in a commit message of the change (`This reverts
commit <sha>.` and GitHub's `Reverts owner/repo#N` are read the same way).

    python3 tools/check_pr_reverts.py                    # origin/main … HEAD
    python3 tools/check_pr_reverts.py --base B --head H [--body-file F]

Exit 0 when nothing is undone, 1 with the undone commits and their paths
otherwise, 2 when the history needed to tell is not there (a shallow clone):
a guard that cannot see must not pass.
"""
import argparse
import os
import re
import subprocess
import sys

ZERO = "0" * 40

# How far back on main a stale tree is recognised. main moves by twenty to
# thirty commits a day, so this is about a week of it; the cost is one
# `git diff-tree --stdin` over the window, well under a second.
WINDOW = 200

# Files made to be deleted (see the module text).
OPEN_NOTE = re.compile(r"tools/fuzz/holes/open/t(\d+)\.md$")
FRAGMENTS = "changes/unreleased/"
CHANGELOG = "CHANGELOG.md"
# An Agora task as the change's text names it: `AGORA-545`, the spelling
# docs/agents/issue-tracker.md asks for (GitHub links a bare `#545` to its
# own pull request 545), or `#545` as older changes wrote it; not
# `github#545`.
TASK_REF = re.compile(r"(?:\bAGORA-|(?<![\w#])#)(\d+)\b")

# `reverts: <what>` at the start of a line; `<what>` is a list of shas and
# pull request numbers.
REVERTS_LINE = re.compile(
    r"^\s*(?:this\s+)?reverts?\b:?\s*(?:commits?\s+)?(.+)$", re.I | re.M)
SHA = re.compile(r"\b[0-9a-f]{7,40}\b", re.I)
PR_REF = re.compile(r"#(\d+)\b")
PR_OF_SUBJECT = re.compile(r"\(#(\d+)\)\s*$")


class NoHistory(Exception):
    pass


def git(args, repo, stdin=None):
    r = subprocess.run(["git", "-C", repo, "-c", "core.quotePath=false"] + args,
                       input=stdin, capture_output=True)
    if r.returncode != 0:
        raise NoHistory("git %s: %s" % (" ".join(args[:2]),
                                        r.stderr.decode("utf-8", "replace").strip()))
    return r.stdout


def raw_entries(out):
    """`git diff --raw -z` / `git diff-tree --stdin -z` output as a list of
    ("commit", sha) and ("entry", old, new, status, [paths])."""
    toks = out.split(b"\0")
    items, i = [], 0
    while i < len(toks):
        t = toks[i].decode("utf-8", "surrogateescape")
        i += 1
        if not t:
            continue
        if t.startswith(":"):
            _, _, old, new, status = t.split(" ")
            n = 2 if status[0] in "RC" else 1
            paths = [p.decode("utf-8", "surrogateescape") for p in toks[i:i + n]]
            i += n
            items.append(("entry", old, new, status, paths))
        else:
            items.append(("commit", t.strip()))
    return items


def window_commits(repo, tip, n):
    """main's first-parent commits ending at `tip`, oldest first, as
    (sha, first parent or None, subject)."""
    out = git(["log", "--first-parent", "-n", str(n), "--format=%H%x09%P%x09%s", tip],
              repo).decode("utf-8", "replace")
    commits = []
    for line in out.splitlines():
        sha, parents, subject = line.split("\t", 2)
        parents = parents.split()
        commits.append((sha, parents[0] if parents else None, subject))
    commits.reverse()
    return commits


def timelines(repo, commits):
    """For every path a window commit touched: [v0, v1 … vk] and [c1 … ck]
    (indexes into `commits`). Also each commit's own list of paths."""
    # `<commit> <parent>` on stdin compares the commit with that parent
    # alone, so a merge commit on main is read by its first parent.
    feed = "".join("%s %s\n" % (sha, parent) if parent else "%s\n" % sha
                   for sha, parent, _ in commits)
    out = git(["diff-tree", "--stdin", "--root", "-r", "--raw", "--no-abbrev", "-z"],
              repo, feed.encode())
    index = {sha: i for i, (sha, _, _) in enumerate(commits)}
    versions, touched_by, paths_of = {}, {}, [[] for _ in commits]
    cur = None
    for item in raw_entries(out):
        if item[0] == "commit":
            cur = index[item[1].split()[0]]
            continue
        _, old, new, _, paths = item
        p = paths[0]
        if p not in versions:
            versions[p] = [old]
            touched_by[p] = []
        versions[p].append(new)
        touched_by[p].append(cur)
        paths_of[cur].append(p)
    return versions, touched_by, paths_of


def head_changes(repo, base, head):
    """{path: blob at head} for every path the head changes against `base`,
    and the set of paths it only moved somewhere else."""
    # Only an exact rename counts (-M100%): the blob main has survives under
    # the new name. That is decided by blob id, like everything else here,
    # so it reads no file content and works in a blob-less clone; and a stale
    # tree's deletion of a new test cannot pair up with a similar new file.
    out = git(["diff", "--raw", "--no-abbrev", "-z", "-M100%", base, head], repo)
    blob, moved = {}, set()
    for item in raw_entries(out):
        _, _, new, status, paths = item
        if status[0] == "R":
            moved.add(paths[0])
            blob[paths[1]] = new
        else:
            blob[paths[0]] = new
    return blob, moved


def allowed(texts, commits):
    """Indexes of the window commits that `reverts:` lines name."""
    shas, prs = [], set()
    for text in texts:
        for m in REVERTS_LINE.finditer(text or ""):
            shas += [s.lower() for s in SHA.findall(m.group(1))]
            prs |= set(PR_REF.findall(m.group(1)))
    ok = set()
    for i, (sha, _, subject) in enumerate(commits):
        m = PR_OF_SUBJECT.search(subject)
        if any(sha.startswith(s) for s in shas) or (m and m.group(1) in prs):
            ok.add(i)
    return ok


def change_text(repo, base, head):
    """The merge-base, and the commit messages of the change."""
    mb = git(["merge-base", base, head], repo).decode().strip()
    return mb, git(["log", "--format=%B", "%s..%s" % (mb, head)], repo).decode("utf-8", "replace")


def made_to_be_deleted(path, fold, tasks):
    m = OPEN_NOTE.match(path)
    return (m is not None and m.group(1) in tasks) or (fold and path.startswith(FRAGMENTS))


def undone(repo, mb, head, texts=(), window=WINDOW):
    """([commits], [(index, rolled-back paths)], {path: head blob}): the
    commits among main's last `window` up to the merge-base `mb` that the
    head undoes, oldest first. `texts` is what the change says of itself."""
    tasks = {n for text in texts for n in TASK_REF.findall(text or "")}
    commits = window_commits(repo, mb, window)
    if len(commits) < window and git(["rev-parse", "--is-shallow-repository"],
                                     repo).strip() == b"true":
        raise NoHistory("only %d of main's commits before %s are in this clone"
                        % (len(commits), mb[:8]))
    versions, touched_by, paths_of = timelines(repo, commits)
    blob, moved = head_changes(repo, mb, head)
    fold = CHANGELOG in blob

    # Per path: the timeline position the head's blob stands at, or None
    # when the head leaves the path as main has it or gives it new content.
    back_to = {}
    for p, h in blob.items():
        if p in moved or p not in versions:
            continue
        vs = versions[p]
        if h == vs[-1]:
            continue                           # a mode change: main's content
        for j in range(len(vs) - 2, -1, -1):
            if vs[j] == h:
                back_to[p] = j
                break

    found = []
    for i, paths in enumerate(paths_of):
        rolled, kept = [], False
        for p in paths:
            if p not in blob or p in moved:
                kept = True
                continue
            if p not in back_to:
                continue                       # content of the head's own
            # This commit is the (n+1)-th to touch p; it made version n+1.
            n = touched_by[p].index(i)
            if back_to[p] > n:
                kept = True
            elif blob[p] == ZERO and made_to_be_deleted(p, fold, tasks):
                continue                       # neither
            else:
                rolled.append(p)
        if rolled and not kept:
            found.append((i, sorted(rolled)))
    return commits, found, blob


def report(mb, commits, found, head_blob):
    lines = ["check_pr_reverts: this change undoes %d commit%s already on main "
             "(merge-base %s):" % (len(found), "" if len(found) == 1 else "s", mb[:8]), ""]
    for i, rolled in found:
        sha, _, subject = commits[i]
        lines.append("  %s %s" % (sha[:8], subject if len(subject) <= 110
                                  else subject[:107] + "…"))
        gone = [p for p in rolled if head_blob.get(p) == ZERO]
        back = [p for p in rolled if head_blob.get(p) != ZERO]
        for what, ps in (("deleted again", gone), ("back at an older version", back)):
            if ps:
                shown = ps[:6] + (["… %d more" % (len(ps) - 6)] if len(ps) > 6 else [])
                lines.append("      %s: %s" % (what, ", ".join(shown)))
    oldest = commits[found[0][0]]
    notes = sorted({OPEN_NOTE.match(p).group(1) for _, rolled in found for p in rolled
                    if OPEN_NOTE.match(p) and head_blob.get(p) == ZERO})
    lines += [
        "",
        "Nothing of %s is kept: where the change touches it, the tree stands where"
        % ("this commit" if len(found) == 1 else "these commits"),
        "main stood before %s. The usual cause is a squash made with" % oldest[0][:8],
        "`git reset --soft origin/main && git commit` on a branch that was not rebased",
        "onto that origin/main: the commit's tree is older than its parent.",
        "",
        "  Not intended:  git fetch origin && git rebase origin/main",
        "                 and squash, if you squash, onto the merge-base:",
        "                 git reset --soft \"$(git merge-base HEAD origin/main)\" && git commit",
        "  Intended:      add a line to the pull request body, then re-run this job:",
        "                 reverts: %s" % ", ".join(commits[i][0][:8] for i, _ in found),
    ]
    if notes:
        lines += [
            "  Closing a hole: the change that deletes tools/fuzz/holes/open/t<N>.md names",
            "                 its task in the pull request title or body (%s)."
            % ", ".join("AGORA-" + n for n in notes),
        ]
    return "\n".join(lines)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--repo", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap.add_argument("--base", default="origin/main", help="main as the change lands on it")
    ap.add_argument("--head", default="HEAD", help="the change's head commit")
    ap.add_argument("--window", type=int, default=WINDOW,
                    help="how many of main's commits to look back over (default %d)" % WINDOW)
    ap.add_argument("--body-file",
                    help="the pull request's title and body: its `reverts:` lines, "
                         "and the tasks it names")
    a = ap.parse_args(argv)

    try:
        mb, messages = change_text(a.repo, a.base, a.head)
        texts = [messages]
        if a.body_file:
            with open(a.body_file, encoding="utf-8", errors="replace") as f:
                texts.append(f.read())
        commits, found, head_blob = undone(a.repo, mb, a.head, texts, a.window)
    except NoHistory as e:
        print("check_pr_reverts: cannot tell: %s\n"
              "(a shallow clone? this needs main's history: git fetch --unshallow, "
              "or `fetch-depth: 0` in the workflow)" % e, file=sys.stderr)
        return 2

    ok = allowed(texts, commits)
    named = [(i, r) for i, r in found if i in ok]
    found = [(i, r) for i, r in found if i not in ok]
    for i, _ in named:
        print("check_pr_reverts: reverts %s, as the change says" % commits[i][0][:8])
    if not found:
        print("check_pr_reverts: ok (%d of main's commits before %s looked at)"
              % (len(commits), mb[:8]))
        return 0
    text = report(mb, commits, found, head_blob)
    print(text, file=sys.stderr)
    if os.environ.get("GITHUB_ACTIONS"):
        print("::error title=This change undoes commits already on main::%s"
              % ", ".join("%s %s" % (commits[i][0][:8], commits[i][2][:80])
                          for i, _ in found[:5]))
    return 1


if __name__ == "__main__":
    sys.exit(main())

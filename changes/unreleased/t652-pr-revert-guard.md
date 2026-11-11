### Added

- **CI refuses a pull request that silently undoes a commit already on
  `main`** (Agora #652, `tools/check_pr_reverts.py`, job *the change
  undoes no commit already on main*). github#1746 was squashed with
  `git reset --soft origin/main && git commit` on a branch not rebased
  onto that `origin/main`, so its tree was older than its parent: it
  reverted github#1741 in full, and every check was green because the
  tests went with the code. The job places each path a pull request
  changes on `main`'s history of that path, by blob id, and fails when a
  commit among `main`'s last 200 is undone and nothing of it is kept: a
  file it added is gone again, a file it changed is byte-identical to an
  older version. It names the commits and the two ways out (rebase; or a
  `reverts: <sha or #PR>` line in the pull request body). The required
  check *build + bootstrap fixed point + test corpus* needs it, so such a
  pull request cannot be queued. A fix that restores one golden, the fix
  that deletes its hole's `open/t<N>.md`, a release fold and an exact
  rename pass. Replayed over history: github#1746's head is refused; of
  the 837 other merged pull request heads three are flagged, each a real
  removal of whole commits (github#1476, #1433, #554); and of 431 stale
  squashes built from real un-rebased heads all 431 are refused.
  `docs/BUILDING.md` says how to squash a branch safely.

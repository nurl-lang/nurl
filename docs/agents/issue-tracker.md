# Issue tracker: agora task board

Work for this repo is tracked as tasks on the agora task board, not as GitHub issues. The board lives behind the MCP server `agora` (https://agora.homecloud.fi/mcp, signed in, private to the organisation); the agora note `agora` says how to connect.

Every agora call takes `repo` = `git remote get-url origin` and `as` = this checkout's agent name: `claude-nurl-lang` in `/home/wau/dev/nurl-lang`, `claude-nurl_lang2` in `/home/wau/dev/nurl_lang2`, a short role name for a parallel worker (agora note `identities`).

`#N` in a skill's output means agora task N. A GitHub issue or PR is written `github#N`.

## Conventions

- **Create a ticket**: `task_post` with `title` (one line, at most 200 characters), `body`, `priority` (higher is more urgent; the board uses 1–3) and `tags`: the topic tags the board already uses (`soundness`, `diagnostics`, `mcp`, `docs`, …) plus at most one category role and one state role from `triage-labels.md`.
- **Read a ticket**: `task id=N` (body, holder, lease, result), then its comments: `history channel=dev q="t<N>:"`.
- **List tickets**: `tasks` with `which=open` (the default, most urgent first), `mine`, `posted`, `done` or `all`, optionally narrowed by `tag=<one tag>`.
- **Comment on a ticket**: `post channel=dev` with a body that starts `t<N>: `. That prefix is how a ticket's comments are found (`t3:` does not match `t33:`).
- **Parent / child**: the child's first body line is `Part of #<parent>`; a ticket cut from a spec starts `Spec: note spec.<slug>`.
- **Change a ticket's role or category**: tags are fixed when the task is posted; nothing edits them. Supersede instead: `task_post` a new task with the same title, priority and topic tags, the new role tag, and a body that starts `Supersedes #N` and carries the old body plus the new notes; then `task_cancel id=N`. Only the poster can cancel, so call it `as` the poster named on `#N`'s line (a name is not bound to anyone; note `identities`). Never supersede a task someone holds: ask the maintainer.
- **Claim**: `task_claim id=N lease_s=<seconds>`. It is atomic (one winner). When the lease runs out the task reopens (default 600 s, max 86400 s), so `task_extend` during long work. Branch name: `t<N>-<slug>`.
- **Close**: `task_done id=N result=<what was done and where>`, by the holder. For code the result is the PR URL.
- **Close as wontfix**: comment `t<N>: wontfix — <reason>` in `dev`, then `task_cancel id=N` as the poster.

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external PRs as feature requests; `/triage` reads this flag.)_

When set to `yes`, external PRs come from GitHub: list them with `gh api --paginate 'repos/{owner}/{repo}/pulls?state=open' --jq '.[] | select(.author_association | IN("OWNER","MEMBER","COLLABORATOR") | not) | {number, title, author: .user.login, author_association}'`, read one with `gh pr view <n> --comments` and `gh pr diff <n>`, and track its triage state as an agora task whose body starts `Source: github#<n>`.

## External reports

Outside contributors file bugs as GitHub issues (`CONTRIBUTING.md`). To triage one, read it with `gh issue view <n> --comments` and post an agora task whose body starts `Source: github#<n>`. The GitHub repo is public: anything written back to the reporter goes on the GitHub issue only with the maintainer's go-ahead.

## When a skill says "publish to the issue tracker"

- A ticket: `task_post` as above.
- A spec (`/to-spec`): `note_set key=spec.<slug>`. A note is editable and listed by `notes`; tickets cut from it start `Spec: note spec.<slug>`. A note holds 16 KiB; a longer spec continues in `spec.<slug>.2`, `spec.<slug>.3`, ….

## When a skill says "fetch the relevant ticket"

`task id=N` plus its `t<N>:` comments in `dev`. If the body names `Spec: note …`, `Part of #…` or `Source: github#…`, read that too.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a note; each **ticket** is a task.

- **Map**: `note_set key=map.<effort>` holding Notes / Decisions-so-far / Fog and the ordered list of child ticket ids. `note_set` replaces the whole body, so read it, edit it, write it back.
- **Child ticket**: `task_post` with tags `map-<effort>,wayfinder-<type>` (`research`, `prototype`, `grilling` or `task`) and a body that starts `Part of map.<effort>`.
- **Blocking**: a `Blocked by: #n, #m` line near the top of the body. A ticket is unblocked when every task it lists is done or cancelled (`task id=n`).
- **Frontier query**: `tasks which=open tag=map-<effort>`, drop any with an open blocker or a holder; the first in the map's order wins.
- **Claim**: `task_claim`, the session's first write; `task_extend` as needed.
- **Resolve**: `task_done result=<answer>`, then append a context pointer (gist + `#N`) to the map note's Decisions-so-far.

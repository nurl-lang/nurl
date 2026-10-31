# Unreleased changes

One file per change, named after its Agora task or pull request
(`t205-try-nc-lend.md`, `pr1353.md`). No pull request edits
`CHANGELOG.md` between releases: two PRs that each appended to its
`[Unreleased]` section always conflicted there, and the second one had to
rebase and run CI again (Agora #211).

A fragment starts with a [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
section heading, followed by the entry exactly as it will read in
`CHANGELOG.md`:

```markdown
### Fixed

- **A try hands the caller only an error it owns** (Agora #205). …
```

Sections: Added, Changed, Deprecated, Removed, Performance, Fixed,
Security, Known issues. One fragment may hold several entries and several
sections.

- `tools/changelog.py check`: every fragment is well formed (CI runs it).
- `tools/changelog.py preview`: CHANGELOG.md with the fragments shown under
  `[Unreleased]` (the playground image serves this).
- `tools/changelog.py fold X.Y.Z`: the release step (RELEASING.md step 1).

# Git hooks

Version-controlled hooks for this repo. Activate them once per clone:

```bash
git config core.hooksPath .githooks
```

(`build.sh` runs this for you, so a normal build already wires them up.)

## `pre-commit`

Runs `nurlfmt` on staged `.nu` files so a commit is always canonical and
never trips the CI `nurlfmt --check` gate:

- **fully staged** files are `nurlfmt --write`-formatted and re-staged;
- **partially staged** files are only `--check`ed (auto-writing would stage
  the unstaged edits too) and block the commit if not canonical.

`bench/` is excluded (recorded model outputs must keep their exact bytes).
It skips cleanly if `build/nurlfmt` isn't built yet, and can be bypassed with
`git commit --no-verify`.

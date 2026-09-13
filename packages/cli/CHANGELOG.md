# Changelog

## 0.3.0

`cli_free` now takes a **`sink`** parameter.

The compiler-ownership hardening in the toolchain (#1107) reached these
signatures: a free function must consume the handle it releases, so the
checker can prove the caller cannot use it again. The change landed in the
monorepo at the time but this package was never republished, so the
registry has been serving 0.2.1 — the same version number, different
source — ever since. That is what this release closes.

For a caller the effect is the ownership rule, not the call: the value is
gone after the free, and using it again is now a compile error instead of a
use-after-free. Code that already treated it that way needs no edit.

## 0.2.0

Driven by migrating yoloe, redis and psql onto the facade:

- **`cli_default c handler`** — register a default command for programs that
  *are* the command (psql/redis-cli shape): a bare invocation runs it instead
  of printing usage, and a first positional that matches no subcommand (e.g.
  a `redis://…` connection URL) routes to it and stays readable as
  `ctx_arg 0`. Registered subcommands still win; the default is hidden from
  the help's command list and the usage line shows `[COMMAND]`.
- **Automatic help-short yield** — when a user flag claims short `-h`
  (psql-style `-h HOST`), the built-in help drops its short and remains
  reachable as `--help`.
- `ctx_arg` / `ctx_nargs` are default-command-aware (no command token to
  skip when the ctx carries an empty command name).

## 0.1.0

Initial release: `Cli` builder over std/args + std/term + ext/env —
subcommand dispatch, typed global flags with env fallbacks and defaults,
coloured `--help`/`--version`, exit-code conventions, and interactive
prompts (`cli_prompt` / `cli_confirm` / `cli_password`).

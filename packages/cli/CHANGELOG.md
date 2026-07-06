# Changelog

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

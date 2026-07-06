# cli — the command-line framework for NURL

One dependency for building a real command-line tool. NURL's stdlib ships a
flat argument parser (`std/args`), terminal control (`std/term` — isatty,
ANSI, a line editor), stdin/stdout (`core/io`), and the environment
(`ext/env`). What it doesn't ship is the glue every tool re-invents: a
subcommand dispatch cascade, typed flag accessors with env fallbacks and
defaults, colour-aware `--help` / `--version` / usage, error → exit-code
handling, and interactive prompts.

`cli` is that glue — a `Cli` object that collapses the 100–500 line
hand-written `main()` every package carries into a declarative handful of
calls.

## Hello, CLI

```nurl
$ `deps/cli/src/cli.nu`

@ main → i {
    : *Cli c ( cli_new `greet` `a tiny greeter` `1.0.0` )
    ( cli_flag_str  c `name` 110 `NAME` `who to greet` `world` `GREET_NAME` )
    ( cli_flag_bool c `loud` 108 `shout it` )
    ( cli_cmd c `hello` `print a greeting` \ CliCtx x → i {
        : String who ( ctx_str x `name` )
        ( nurl_print `hello, ` ) ( nurl_print ( string_data who ) )
        ? ( ctx_bool x `loud` ) { ( nurl_print `!` ) } {}
        ( nurl_print `\n` )
        ( string_free who )
        ^ 0
    } )
    : i rc ( cli_run c )
    ( cli_free c )
    ^ rc
}
```

```
$ greet hello --name Tero --loud
hello, Tero!
$ GREET_NAME=Env greet hello          # env fallback
hello, Env
$ greet --help                        # auto, coloured on a TTY
```

## The API

Construction & run:

| Call | |
| --- | --- |
| `( cli_new prog about version )` → `*Cli` | create (free with `cli_free`) |
| `( cli_run c )` → `i` | parse argv, route to a command, return its exit code |

Flags (global; resolved per command). Each takes `long`, a `short` char code
(0 = none), and — for value flags — a `metavar`, `help`, a default, and an
env-var name (empty `` = none):

| Call | |
| --- | --- |
| `( cli_flag_bool c long short help )` | presence flag |
| `( cli_flag_str  c long short metavar help dflt env )` | string |
| `( cli_flag_int  c long short metavar help dflt env )` | integer (`dflt` is `i`) |
| `( cli_flag_float c long short metavar help dflt env )` | float (`dflt` is `f`) |

Commands — the handler is `( @ i CliCtx )`, returning an exit code:

| Call | |
| --- | --- |
| `( cli_cmd c name help handler )` | register a subcommand |
| `( cli_default c handler )` | the default command — runs on a bare invocation or when no subcommand matches (psql/redis-cli-style tools where the program *is* the command; positionals such as a connection URL stay readable via `ctx_arg`) |

Inside a handler, read from the `CliCtx`:

| Call | |
| --- | --- |
| `( ctx_str x name )` → `String` | value → env → default (owned; free it) |
| `( ctx_int x name )` → `i`, `( ctx_float x name )` → `f` | typed |
| `( ctx_bool x name )` → `b` | flag presence |
| `( ctx_arg x idx )` → `String` | idx-th positional after the command |
| `( ctx_nargs x )` → `i` | positional count |
| `( ctx_stdin x )` → `String` | slurp stdin (pipe-friendly) |
| `( ctx_cmd x )` → `s` | the invoked command name |

Interactive prompts (write to stderr; TTY-aware):

| Call | |
| --- | --- |
| `( cli_prompt question )` → `String` | free-text line |
| `( cli_confirm question def )` → `b` | y/N (or Y/n), `def` on Enter/EOF |
| `( cli_password question )` → `String` | no echo on a TTY |

## Behaviour

- **`--help` / `-h`** — auto-generated global help (usage, aligned command
  list, options with defaults and env vars). `prog <cmd> --help` gives the
  command's help. **`--version`** prints `prog version`. If one of *your*
  flags claims short `-h` (psql-style `-h HOST`), the built-in help
  automatically yields the short and stays reachable as `--help`.
- **Colour** is decided once: on only when stdout is a TTY and `$NO_COLOR`
  is unset. Piped output is plain.
- **Exit codes** — a command returns its own; unknown command or a parse
  error is `2`; a bare invocation with no command prints help and exits `1` —
  unless a `cli_default` is registered, in which case both a bare invocation
  and an unmatched first token route to it (the token becomes `ctx_arg 0`).
- **Flag resolution** — an explicit `--flag` wins, else the bound env var,
  else the declared default.

## Scope

`cli` facades the command-line surface — args, env, stdin, TTY/colour/prompt,
exit codes. It deliberately does **not** absorb terminal widgets
(tables / spinners / progress), config-file loading, or logging; those
compose as their own packages.

## Tests

`./tests/cli_test.sh` builds `tests/demo.nu` (a five-command CLI) and drives
routing, typed flags with env + precedence, positionals, stdin, prompts,
help/version and exit codes — then re-runs the allocating paths under
AddressSanitizer (0 errors, 0 leaks).

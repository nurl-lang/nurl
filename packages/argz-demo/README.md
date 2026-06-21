# `argz-demo` — a friendly greeter built on `argz`

`argz-demo` is a tiny installable CLI that demonstrates the full NURL
package ecosystem end to end. It declares [`argz`](../argz) as a registry
dependency (see `nurl.toml`) and ships a `src/main.nu` entry point, so
`nurlpkg install argz-demo` fetches `argz`, resolves it into `./deps/`,
compiles the program against the installed stdlib, and drops a `argz-demo`
binary on `$PATH`.

```
nurlpkg install argz-demo

argz-demo --name World            # Hello, World!
argz-demo --name World --shout    # HELLO, WORLD!
argz-demo alice bob               # Hello, alice! / Hello, bob!
argz-demo --help                  # usage, rendered by argz
```

## What it shows

- **Dependency resolution** — `argz = "^0.1"` is fetched from the registry
  and linked under `deps/argz/` at install time.
- **The `argz` API in practice** — boolean flags (`--shout`), value options
  (`--name`), positional arguments, and the auto-generated `--help`.
- **The install loop** — fetch → resolve deps → compile against the shipped
  stdlib → binary on `$PATH`.

The interesting code is just one file, [`src/main.nu`](src/main.nu). For the
argument-parser API itself, see [`argz`](../argz).

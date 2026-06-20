# NURL registry packages

Real, publishable packages that exercise the NURL package ecosystem end to
end — the compiler's installed-stdlib resolution (`$NURL_STDLIB`), the
package manager's dependency resolution, and `nurlpkg install <name>`
(fetch + build + install a program from the registry onto `$PATH`).

These are **registry** packages, deliberately *not* part of the core
stdlib: every CLI wants argument parsing, but the shape of a parser is
opinionated enough that it belongs to the ecosystem, not the language.

## `argz/` — a tiny argument parser (library)

Dependency-free. Boolean flags, value options (`--name X` / `--name=X`),
short aliases (`-n`), a `--` end-of-options separator, positional
arguments, and an auto-generated `--help` body. Leak-clean under
AddressSanitizer/LeakSanitizer.

```
( argz_new prog about )           → Argz
( argz_flag p long short help )   → v        bool flag
( argz_opt  p long short help )   → v        value option
( argz_parse p argv )             → ! ArgzMatch ArgzErr
( argz_has   m long )             → b
( argz_value m long )             → ?String  (borrows)
( argz_positionals m )            → ( Vec String )  (borrows)
( argz_help  p )                  → String
```

## `argz-demo/` — a friendly greeter (installable program)

Declares `argz = "^0.1"` as a registry dependency and ships a `src/main.nu`
entry point, so it can be installed as a binary:

```
nurlpkg install argz-demo
argz-demo --name World            # Hello, World!
argz-demo --name World --shout    # HELLO, WORLD!
argz-demo alice bob               # Hello, alice! / Hello, bob!
```

`nurlpkg install <name>` fetches the package, resolves its dependencies
into `./deps/`, compiles `src/main.nu` with the installed compiler against
the shipped stdlib (found via `$NURL_STDLIB`), and drops the binary in
`$NURL_HOME/bin` (default `~/.nurl/bin`, which `install-toolchain.sh` puts
on `$PATH`).

## The full loop

```bash
./build.sh                          # build the compiler
./tools/nurlpkg/build.sh            # build the package manager
./tools/install-toolchain.sh        # install nurlc + nurlpkg + stdlib to ~/.nurl
source ~/.nurl/env                  # NURL_STDLIB + PATH

nurlpkg install argz-demo           # fetch + build + install from the registry
argz-demo --shout hello             # HELLO, HELLO!
```

A self-contained reproduction (a local static registry, no account needed)
lives in `tools/nurlpkg/test-install-tool.sh`.

## Windows

The same loop works on Windows with the `.bat` counterparts:

```bat
build.bat
tools\nurlpkg\build.bat
tools\install-toolchain.bat       :: installs to %USERPROFILE%\.nurl
call %USERPROFILE%\.nurl\env.bat   :: NURL_STDLIB + PATH for this session
nurlpkg install argz-demo
argz-demo --shout hello
```

`nurlpkg install <name>` is shell-free and cross-platform: it stages under
the platform temp dir, resolves the tool's dependencies in-process, copies
the built binary with the language's own filesystem primitives, and runs
the build driver (`nurl.sh` / `nurl.bat`) without any POSIX coreutils. The
compiler finds the shipped stdlib via `$NURL_STDLIB` on both platforms.

### Bin convention

An installable program is any package with a `src/main.nu` entry point; the
installed binary takes the package's name. A package without `src/main.nu`
is a library (like `argz`) and `nurlpkg install <name>` reports it as such.

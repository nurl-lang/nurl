// tools/nurlpkg/main.nu — NURL package manager CLI (v0.4.x).
//
// Subcommands implemented in this iteration:
//
//   nurlpkg init <name>      — create a fresh `nurl.toml` skeleton.
//   nurlpkg info             — read `nurl.toml` and print typed fields.
//   nurlpkg deps             — list dependencies (one per line, pipe-friendly).
//   nurlpkg install          — BFS-resolve path-deps and symlink each one
//                              under `./deps/<name>`. Refuses to overwrite an
//                              existing `deps/<name>` entry; uses libc
//                              `symlink(2)` via pure-NURL FFI.
//                              Regenerates nurl.lock as a side-effect.
//   nurlpkg lock             — regenerate `nurl.lock` from the current
//                              on-disk `deps/` tree.
//   nurlpkg add <name> ...   — append a `[dependencies]` entry. Accepts
//                              `--path P` and/or `--version V`. Refuses
//                              if the name is already declared.
//   nurlpkg remove <name>    — delete the `[dependencies]` entry. Errors
//                              if the name is not declared.
//   nurlpkg verify           — compare `deps/` against `nurl.lock` and
//                              exit 1 on any drift (missing or extra).
//                              Intended for CI / pre-build gates.
//   nurlpkg version          — print the nurlpkg version. `--version`
//                              also accepted for consistency with other
//                              CLIs in the toolchain.
//   nurlpkg help             — usage.
//
// Subcommands deferred to later iterations:
//   build / publish

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/cmp.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/sort.nu`
$ `stdlib/std/process.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/manifest.nu`
$ `stdlib/ext/lockfile.nu`
$ `stdlib/ext/registry_index.nu`
$ `stdlib/ext/resolver.nu`
$ `stdlib/ext/pkg_fetch.nu`
$ `stdlib/ext/pkg_publish.nu`
$ `stdlib/ext/semver.nu`
$ `stdlib/ext/credentials.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/update_check.nu`
$ `stdlib/ext/toolchain.nu`
$ `stdlib/core/io.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/bytes.nu`

// ── registry config ──────────────────────────────────────────────
//
// The registry a bare/registry dependency resolves against, in priority
// order: $NURL_REGISTRY env var → the manifest's [package].registry →
// the built-in default. The env override is the hook tests + air-gapped
// mirrors use to point nurlpkg at a loopback or internal registry.

@ __default_registry → s {
    ^ `https://reg.nurl-lang.org/`
}

@ __registry_url Manifest m → String {
    : ?String ev ( env_get `NURL_REGISTRY` )
    ?? ev {
        T e → { ? > ( string_len e ) 0 { ^ e } { ( string_free e ) } }
        F → {}
    }
    ? > ( string_len . m registry ) 0 {
        ^ ( string_from ( string_data . m registry ) )
    } {}
    ^ ( string_from ( __default_registry ) )
}

// Registry for project-independent commands (login/search/yank): the
// $NURL_REGISTRY override, else the built-in default.
@ __reg_default → String {
    : ?String ev ( env_get `NURL_REGISTRY` )
    ?? ev {
        T e → { ? > ( string_len e ) 0 { ^ e } { ( string_free e ) } }
        F → {}
    }
    ^ ( string_from ( __default_registry ) )
}

// Publish/yank auth token: $NURL_TOKEN first, then the stored credential
// for `registry` (from `nurlpkg login`). Returns "" if neither is set.
@ __resolve_token s registry → String {
    : ?String ev ( env_get `NURL_TOKEN` )
    ?? ev {
        T e → { ? > ( string_len e ) 0 { ^ e } { ( string_free e ) } }
        F → {}
    }
    ^ ( creds_get registry )
}

// Free a Dep vector built by __registry_roots (each Dep + the vector).
@ __deps_free_vec ( Vec Dep ) v → v {
    : i n ( vec_len [Dep] v )
    : ~ i k 0
    ~ < k n {
        : ?Dep dk ( vec_get [Dep] v k )
        ?? dk { T d → ( dep_free d ) F _ → {} }
        = k + k 1
    }
    ( vec_free [Dep] v )
}

// Dependencies that must be resolved from the registry at install time:
//   * pure registry deps (no path), and
//   * `{ path, version }` hybrids whose local path target is ABSENT — e.g.
//     a registry install (`nurlpkg install <name>`) extracts the package
//     into a temp dir where the sibling `../onnx` path doesn't exist, so
//     the dep falls back to its registry `version`.
// Hybrids whose path IS present on disk are left to the path-dep BFS and
// excluded here (no double install). Returned hybrids have their `path`
// cleared so `resolve_registry` seeds them as registry roots. Caller owns
// the returned vector (free each Dep).
@ __registry_roots Manifest m s cwd → ( Vec Dep ) {
    : ( Vec Dep ) out ( vec_new [Dep] )
    : i n ( vec_len [Dep] . m dependencies )
    : ~ i k 0
    ~ < k n {
        : ?Dep dk ( vec_get [Dep] . m dependencies k )
        ?? dk {
            T d → {
                : ~ b take F
                : ~ b clearpath F
                ? ( dep_is_registry d ) { = take T } {
                    ? ( dep_has_version d ) {
                        : String tgt ( __abs_join cwd ( string_data . d path ) )
                        ? ! ( __dep_has_manifest ( string_data tgt ) ) { = take T = clearpath T } {}
                        ( string_free tgt )
                    } {}
                }
                ? take {
                    : String p ? clearpath ( string_new ) ( string_from ( string_data . d path ) )
                    ( vec_push [Dep] out @ Dep {
                        ( string_from ( string_data . d name ) )
                        p
                        ( string_from ( string_data . d version ) )
                        ( string_from ( string_data . d registry ) )
                    } )
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ out
}

// Build the X-Nurl-Deps JSON array of { name, req } from a manifest's
// dependencies that carry a registry version requirement. A Cargo-style
// `{ path = "...", version = "..." }` hybrid IS published (its `version`
// is the requirement a downstream consumer resolves from the registry —
// the `path` is only a local-dev override). Pure path deps (no version)
// are local-only and excluded. Names/reqs are simple tokens (no
// JSON-special chars), so a direct build is safe. Empty deps → "[]".
@ __deps_json Manifest m → String {
    : String out ( string_with_cap 64 )
    ( string_push_char out 91 )  // [
    : i n ( vec_len [Dep] . m dependencies )
    : ~ i first 1
    : ~ i k 0
    ~ < k n {
        : ?Dep dk ( vec_get [Dep] . m dependencies k )
        ?? dk {
            T d → {
                ? ( dep_has_version d ) {
                    ? == first 0 { ( string_push_char out 44 ) } {}  // ,
                    = first 0
                    ( string_push_str out `{"name":"` )
                    ( string_push_str out ( string_data . d name ) )
                    ( string_push_str out `","req":"` )
                    ( string_push_str out ( string_data . d version ) )
                    ( string_push_str out `"}` )
                } {}
            }
            F → {}
        }
        = k + k 1
    }
    ( string_push_char out 93 )  // ]
    ^ out
}

// Index of the registry LockPkg named `name`, or -1.
@ __reg_lookup ( Vec LockPkg ) regpkgs s name → i {
    : i n ( vec_len [LockPkg] regpkgs )
    : ~ i k 0
    ~ < k n {
        : ?LockPkg po ( vec_get [LockPkg] regpkgs k )
        ?? po { T p → { ? != 0 ( nurl_str_eq ( string_data . p name ) name ) { ^ k } {} } F → {} }
        = k + k 1
    }
    ^ -1
}

// ── usage ────────────────────────────────────────────────────────

@ __print_usage → v {
    ( nurl_print `nurlpkg — NURL package manager\n\n` )
    ( nurl_print `Usage:\n` )
    ( nurl_print `  nurlpkg init <name>    Create a new nurl.toml in the current directory.\n` )
    ( nurl_print `  nurlpkg info           Print the parsed manifest in the current directory.\n` )
    ( nurl_print `  nurlpkg deps           List dependencies, one per line.\n` )
    ( nurl_print `  nurlpkg install        Resolve this project's deps and symlink them under ./deps/.\n` )
    ( nurl_print `  nurlpkg install <name> Program: fetch, build + install onto $PATH. Library: install under ./deps/ (no nurl.toml needed).\n` )
    ( nurl_print `  nurlpkg lock           Regenerate nurl.lock from the current deps/ tree.\n` )
    ( nurl_print `  nurlpkg publish [--dry-run]  Pack + upload this package to the registry\n` )
    ( nurl_print `                         (--dry-run: run every gate, upload nothing).\n` )
    ( nurl_print `  nurlpkg build [<dep>] [--out PATH]\n` )
    ( nurl_print `                         Compile a package's src/main.nu in place (this\n` )
    ( nurl_print `                         package, or an installed deps/<dep> application).\n` )
    ( nurl_print `  nurlpkg login          Store a publish token in ~/.nurl/credentials.\n` )
    ( nurl_print `  nurlpkg logout [--revoke]  Forget the local token (and optionally revoke it).\n` )
    ( nurl_print `  nurlpkg search <q>     Search the registry for packages.\n` )
    ( nurl_print `  nurlpkg info <name>    Show a package's published versions.\n` )
    ( nurl_print `  nurlpkg yank|unyank <name> <version>  Hide/unhide a published version.\n` )
    ( nurl_print `  nurlpkg add <name> [--path P] [--version V]\n` )
    ( nurl_print `                         Add a dependency entry to nurl.toml.\n` )
    ( nurl_print `  nurlpkg remove <name>  Delete a dependency entry from nurl.toml.\n` )
    ( nurl_print `  nurlpkg update [<name>...] [--all]\n` )
    ( nurl_print `                         Move dependency requirements to the newest versions\n` )
    ( nurl_print `                         (asks y/N per dependency; --all updates everything).\n` )
    ( nurl_print `  nurlpkg verify         Check deps/ matches nurl.lock (names + versions); exit 1 if drift.\n` )
    ( nurl_print `  nurlpkg test           Build + run every tests/*.nu (exit 0 = pass; optional tests/outputs/ goldens).\n` )
    ( nurl_print `  nurlpkg bench          Build + run every benches/*.nu and stream their std/bench.nu reports.\n` )
    ( nurl_print `  nurlpkg self-update [--check] [--version vX.Y.Z] [--force]\n` )
    ( nurl_print `                         Upgrade the NURL TOOLCHAIN itself (same as 'nurl upgrade').\n` )
    ( nurl_print `                         Note: 'nurlpkg update' is about this project's dependencies.\n` )
    ( nurl_print `  nurlpkg version        Print the toolchain version (--version / -v too).\n` )
    ( nurl_print `  nurlpkg help [<cmd>]   This message, or one command's own help.\n` )
    ( nurl_print `\nEvery command also takes --help / -h (help never runs the command).\n` )
}

// ── per-command help + flag safety ──────────────────────────────
// `nurlpkg <cmd> --help` (or -h, or `nurlpkg help <cmd>`) prints the
// command's own help and DOES NOTHING ELSE. This is checked before any
// command runs — an agent probing `nurlpkg publish --help` must never
// trigger a publish. Returns F for an unknown command.
@ __cmd_help s cmd → b {
    ? | | != 0 ( nurl_str_eq cmd `self-update` ) != 0 ( nurl_str_eq cmd `upgrade` ) != 0 ( nurl_str_eq cmd `self-upgrade` ) {
        ( nurl_print `nurlpkg self-update — upgrade the NURL toolchain itself

` )
        ( nurl_print `Usage: nurlpkg self-update [--check] [--version vX.Y.Z] [--force]
` )
        ( nurl_print `       nurl upgrade [...]          the canonical spelling; same command

` )
        ( nurl_print `Downloads the release that matches this machine and unpacks it over the
` )
        ( nurl_print `current install prefix ($NURL_HOME), verifying the checksum and (when
` )
        ( nurl_print `minisign is present) the signature. USER STATE in the prefix is kept:
` )
        ( nurl_print `the registry token, ~/.nurl/models, and every program you installed
` )
        ( nurl_print `with 'nurlpkg install' stay exactly where they are.

` )
        ( nurl_print `Flags:
` )
        ( nurl_print `  --check            Report whether an update exists; install nothing.
` )
        ( nurl_print `  --version <tag>    Install a specific release (pin, or go back).
` )
        ( nurl_print `  --force            Reinstall the same version, or replace a dev build.
` )
        ( nurl_print `  --help             This message (nothing is installed).

` )
        ( nurl_print `Not to be confused with 'nurlpkg update', which moves THIS PROJECT's
` )
        ( nurl_print `dependency requirements to newer versions.
` )
        ^ T
    } {}
    ? != 0 ( nurl_str_eq cmd `publish` ) {
        ( nurl_print `nurlpkg publish — pack this package and upload it to the registry

` )
        ( nurl_print `Usage: nurlpkg publish [--dry-run]

` )
        ( nurl_print `Runs every gate first, in order:
` )
        ( nurl_print `  1. nurl.toml parses; name + version present
` )
        ( nurl_print `  2. every deps/... import is declared in [dependencies]
` )
        ( nurl_print `  3. every imported stdlib file exists in the RELEASED toolchain, and
     src/main.nu typechecks against it
` )
        ( nurl_print `  4. path-deps carry a version requirement
` )
        ( nurl_print `  5. requirements match the LOCAL copies you built against
` )
        ( nurl_print `then packs the tarball, prints name/version/size/sha256, and uploads.

` )
        ( nurl_print `Flags:
` )
        ( nurl_print `  --dry-run   Run every gate and pack, print exactly what WOULD be
` )
        ( nurl_print `              uploaded and where — but upload nothing. Needs no token.
` )
        ( nurl_print `  --help      This message (nothing is published).

` )
        ( nurl_print `Publishing is IRREVERSIBLE (a version can be yanked but not replaced).
` )
        ( nurl_print `Auth: 'nurlpkg login' or $NURL_TOKEN. Tokens expire after 90 days.
` )
        ^ T
    } {}
    ? != 0 ( nurl_str_eq cmd `install` ) {
        ( nurl_print `nurlpkg install — resolve dependencies, or install a tool

` )
        ( nurl_print `Usage: nurlpkg install            resolve this project's [dependencies]
` )
        ( nurl_print `                                  into ./deps/ (registry + path deps)
` )
        ( nurl_print `       nurlpkg install <name>     fetch a published package; a PROGRAM
` )
        ( nurl_print `                                  (has src/main.nu) is built + put on
` )
        ( nurl_print `                                  $PATH, a LIBRARY lands under ./deps/
` )
        ^ T
    } {}
    ? != 0 ( nurl_str_eq cmd `build` ) {
        ( nurl_print `nurlpkg build — compile a package's src/main.nu in place

` )
        ( nurl_print `Usage: nurlpkg build              this package: deps resolve, then
` )
        ( nurl_print `                                  src/main.nu -> ./<name>
` )
        ( nurl_print `       nurlpkg build <dep>        an installed deps/<dep> (application
` )
        ( nurl_print `                                  packages build from their own root —
` )
        ( nurl_print `                                  the deps link is arranged for you)
` )
        ( nurl_print `       ... [--out PATH]           write the binary somewhere else
` )
        ^ T
    } {}
    ? != 0 ( nurl_str_eq cmd `add` ) {
        ( nurl_print `nurlpkg add — add a dependency to nurl.toml

` )
        ( nurl_print `Usage: nurlpkg add <name> [--path P] [--version V]

` )
        ( nurl_print `Registry dep by default (newest version becomes the requirement);
` )
        ( nurl_print `--path makes a local path dep. Follow with 'nurlpkg install'.
` )
        ^ T
    } {}
    ? != 0 ( nurl_str_eq cmd `update` ) {
        ( nurl_print `nurlpkg update — move requirements to the newest published versions

` )
        ( nurl_print `Usage: nurlpkg update [<name>...] [--all]

` )
        ( nurl_print `Asks y/N per dependency; --all updates everything without asking.
` )
        ( nurl_print `Path deps re-read their local nurl.toml; registry deps ask the index.
` )
        ^ T
    } {}
    ? != 0 ( nurl_str_eq cmd `logout` ) {
        ( nurl_print `nurlpkg logout — forget the stored registry token

` )
        ( nurl_print `Usage: nurlpkg logout [--revoke]

` )
        ( nurl_print `--revoke also invalidates the token server-side.
` )
        ^ T
    } {}
    ? != 0 ( nurl_str_eq cmd `yank` ) {
        ( nurl_print `nurlpkg yank — hide a published version from resolution

` )
        ( nurl_print `Usage: nurlpkg yank <name> <version>

` )
        ( nurl_print `Yanking hides; it never deletes. 'nurlpkg unyank' restores.
` )
        ^ T
    } {}
    ? != 0 ( nurl_str_eq cmd `unyank` ) {
        ( nurl_print `nurlpkg unyank — restore a yanked version

Usage: nurlpkg unyank <name> <version>
` )
        ^ T
    } {}
    ? != 0 ( nurl_str_eq cmd `init` ) {
        ( nurl_print `nurlpkg init — create a nurl.toml here

Usage: nurlpkg init <name>
` )
        ^ T
    } {}
    ? != 0 ( nurl_str_eq cmd `info` ) {
        ( nurl_print `nurlpkg info — manifest / registry info

` )
        ( nurl_print `Usage: nurlpkg info           parsed nurl.toml of this directory
` )
        ( nurl_print `       nurlpkg info <name>    a package's published versions
` )
        ^ T
    } {}
    ? != 0 ( nurl_str_eq cmd `search` ) {
        ( nurl_print `nurlpkg search — search the registry

Usage: nurlpkg search <query>
` )
        ^ T
    } {}
    ? != 0 ( nurl_str_eq cmd `deps` ) {
        ( nurl_print `nurlpkg deps — list this package's dependencies

Usage: nurlpkg deps
` )
        ^ T
    } {}
    ? != 0 ( nurl_str_eq cmd `lock` ) {
        ( nurl_print `nurlpkg lock — regenerate nurl.lock from ./deps/

Usage: nurlpkg lock
` )
        ^ T
    } {}
    ? != 0 ( nurl_str_eq cmd `verify` ) {
        ( nurl_print `nurlpkg verify — check deps/ against nurl.lock

Usage: nurlpkg verify   (exit 1 on drift)
` )
        ^ T
    } {}
    ? != 0 ( nurl_str_eq cmd `remove` ) {
        ( nurl_print `nurlpkg remove — delete a dependency entry

Usage: nurlpkg remove <name>
` )
        ^ T
    } {}
    ? != 0 ( nurl_str_eq cmd `test` ) {
        ( nurl_print `nurlpkg test — build + run every tests/*.nu

Usage: nurlpkg test   (optional tests/outputs/ goldens; exit 0 = pass)

Compiles with the installed nurl (a toolchain checkout's ./nurl.sh wins when
you run from one); $NURL_CC overrides with your own <flags> <src> <out> driver.
` )
        ^ T
    } {}
    ? != 0 ( nurl_str_eq cmd `bench` ) {
        ( nurl_print `nurlpkg bench — build + run every benches/*.nu

Usage: nurlpkg bench
` )
        ^ T
    } {}
    ? != 0 ( nurl_str_eq cmd `login` ) {
        ( nurl_print `nurlpkg login — store a publish token

Usage: nurlpkg login   (paste the token from the registry; kept in ~/.nurl/credentials)
` )
        ^ T
    } {}
    ^ F
}

// T when any argv[from..] is --help / -h. Checked before dispatch, so a
// help probe can never execute the command it asks about.
@ __wants_help i from → b {
    : i argc ( env_args_count )
    : ~ i k from
    ~ < k argc {
        : String a ( env_arg k )
        : b hit | != 0 ( nurl_str_eq ( string_data a ) `--help` ) != 0 ( nurl_str_eq ( string_data a ) `-h` )
        ( string_free a )
        ? hit { ^ T } {}
        = k + k 1
    }
    ^ F
}

// Reject any --flag in argv[from..] that is not in `allowed` (space-
// separated). A typo like `publish --dryrun` must FAIL, not fall through
// to the real action.
@ __reject_unknown_flags s cmd s allowed i from → i {
    : i argc ( env_args_count )
    : ~ i k from
    ~ < k argc {
        : String a ( env_arg k )
        : s av ( string_data a )
        ? & >= ( nurl_str_len av ) 2 & == ( nurl_str_get av 0 ) 45 == ( nurl_str_get av 1 ) 45 {
            // `allowed` is space-separated exact flags
            : ~ b okflag F
            : ~ String pad ( string_from ` ` )
            ( string_push_str pad allowed )
            ( string_push_str pad ` ` )
            : ~ String needle ( string_from ` ` )
            ( string_push_str needle av )
            ( string_push_str needle ` ` )
            ? >= ( nurl_str_find ( string_data pad ) ( string_data needle ) ) 0 { = okflag T } {}
            ( string_free pad ) ( string_free needle )
            ? okflag {} {
                ( nurl_eprint `nurlpkg: unknown option '` )
                ( nurl_eprint av )
                ( nurl_eprint `' for '` )
                ( nurl_eprint cmd )
                ( nurl_eprintln `' — nothing was done` )
                ( nurl_eprint `hint: nurlpkg ` )
                ( nurl_eprint cmd )
                ( nurl_eprintln ` --help` )
                ( string_free a )
                ^ 1
            }
        } {}
        ( string_free a )
        = k + k 1
    }
    ^ 0
}

// ── build: compile a package's entry point in place ─────────────
// The missing rung between `install` (deps) and `install <name>` (PATH):
// application packages import root-relative (`src/...`), so in a consumer
// tree deps/<app> would not compile without a deps link back to its
// siblings. `nurlpkg build <app>` arranges that link and builds; bare
// `nurlpkg build` builds the current package.
@ __cmd_build s name s outp → i {
    : ~ String dir ( string_from `.` )
    ? > ( nurl_str_len name ) 0 {
        ( string_free dir )
        = dir ( string_from `deps/` )
        ( string_push_str dir name )
        ? ( file_exists ( string_data dir ) ) {} {
            ( nurl_eprint `nurlpkg: no deps/` )
            ( nurl_eprint name )
            ( nurl_eprintln ` — run 'nurlpkg install' first (or 'nurlpkg add' + install)` )
            ( string_free dir )
            ^ 1
        }
    } {}
    : String entry ( string_from ( string_data dir ) )
    ( string_push_str entry `/src/main.nu` )
    ? ( file_exists ( string_data entry ) ) {} {
        ( nurl_eprintln `nurlpkg: the package has no src/main.nu — it is a library, not a program` )
        ( string_free entry ) ( string_free dir )
        ^ 1
    }
    ( string_free entry )
    // an installed application's deps are its SIBLINGS under ./deps — give
    // it the link its root-relative imports expect (idempotent)
    ? > ( nurl_str_len name ) 0 {
        : String dl ( string_from ( string_data dir ) )
        ( string_push_str dl `/deps` )
        ? ( file_exists ( string_data dl ) ) {} {
            ?? ( fs_symlink `..` ( string_data dl ) ) {
                T _ → {}
                F _ → { ( nurl_eprintln `nurlpkg: warning — could not create the deps link` ) }
            }
        }
        ( string_free dl )
    } {}
    // binary name: --out, else the manifest's name (this dir) / the dep name
    : ~ String binout ( string_new )
    ? > ( nurl_str_len outp ) 0 {
        ( string_push_str binout outp )
    } {
        ? > ( nurl_str_len name ) 0 { ( string_push_str binout name ) } {
            : !Manifest ManifestErr mr0 ( manifest_load `nurl.toml` )
            ?? mr0 {
                T m0 → {
                    ( string_push_str binout ( string_data . m0 name ) )
                    ( manifest_free m0 )
                }
                F _ → { ( string_push_str binout `a.out` ) }
            }
        }
    }
    // absolute-ish output path from the build cwd (the package dir): the
    // caller's name/--out is relative to WHERE THEY RAN nurlpkg
    : ~ String absout ( string_new )
    ? == ( nurl_str_get ( string_data binout ) 0 ) 47 { ( string_push_str absout ( string_data binout ) ) } {
        ?? ( env_cwd ) {
            T c → {
                ( string_push_str absout ( string_data c ) )
                ( string_push_str absout `/` )
                ( string_push_str absout ( string_data binout ) )
                ( string_free c )
            }
            F _ → { ( string_push_str absout ( string_data binout ) ) }
        }
    }
    : String nurl ( __env_or `NURL` `nurl` )
    : ~ String orig ( string_new )
    ?? ( env_cwd ) { T c → { ( string_free orig ) = orig c } F _ → {} }
    : ~ i rc 1
    ?? ( env_chdir ( string_data dir ) ) {
        F _ → { ( nurl_eprintln `nurlpkg: cannot enter the package directory` ) }
        T _ → {
            // resolve the package's own deps first when building in place
            : ~ i drc 0
            ? == ( nurl_str_len name ) 0 { = drc ( __cmd_install ) } {}
            ? != drc 0 { = rc 1 } {
                : ( Vec s ) cargs ( vec_new [s] )
                ( vec_push [s] cargs `src/main.nu` )
                ( vec_push [s] cargs ( string_data absout ) )
                : i ok2 ( __spawn ( string_data nurl ) cargs `compile` )
                ( vec_free [s] cargs )
                ? == ok2 0 { = rc 1 } {
                    = rc 0
                    ( nurl_print `built ` )
                    ( nurl_print ( string_data binout ) )
                    ( nurl_print `\n` )
                }
            }
        }
    }
    ? > ( string_len orig ) 0 { ?? ( env_chdir ( string_data orig ) ) { T _ → {} F _ → {} } } {}
    ( string_free absout ) ( string_free binout )
    ( string_free nurl ) ( string_free orig ) ( string_free dir )
    ^ rc
}

// ── init ────────────────────────────────────────────────────────

@ __cmd_init s name → i {
    ? == 0 ( nurl_str_len name ) {
        ( nurl_eprintln `nurlpkg: 'init' requires a package name` )
        ( nurl_eprintln `Usage: nurlpkg init <name>` )
        ^ 2
    } {}
    ? ( file_exists `nurl.toml` ) {
        ( nurl_eprintln `nurlpkg: nurl.toml already exists in the current directory; refusing to overwrite` )
        ^ 1
    } {}
    : String body ( string_with_cap 256 )
    ( string_push_str body `[package]\n` )
    ( string_push_str body `name = "` )
    ( string_push_str body name )
    ( string_push_str body `"\n` )
    ( string_push_str body `version = "0.1.0"\n` )
    ( string_push_str body `description = ""\n` )
    ( string_push_str body `license = "MIT"\n\n` )
    ( string_push_str body `[dependencies]\n` )
    ( string_push_str body `# Example:\n` )
    ( string_push_str body `# http-router = { path = "../router", version = "0.2.0" }\n` )
    : !v IoErr wr ( write_file `nurl.toml` ( string_data body ) )
    ( string_free body )
    ?? wr {
        T _ → {
            ( nurl_print `Created nurl.toml\n` )
            ^ 0
        }
        F _ → {
            ( nurl_eprintln `nurlpkg: failed to write nurl.toml` )
            ^ 1
        }
    }
}

// ── info ────────────────────────────────────────────────────────

@ __cmd_info → i {
    ? ! ( file_exists `nurl.toml` ) {
        ( nurl_eprintln `nurlpkg: no nurl.toml in the current directory (run 'nurlpkg init <name>' first)` )
        ^ 1
    } {}
    : !Manifest ManifestErr mr ( manifest_load `nurl.toml` )
    : ~ i rc 0
    ?? mr {
        F e → {
            ( nurl_eprint `nurlpkg: failed to parse nurl.toml (` )
            ( nurl_eprint ( manifest_err_name e ) )
            ( nurl_eprintln `)` )
            = rc 1
        }
        T m → {
            ( nurl_print `package:      ` ) ( nurl_print ( string_data . m name ) ) ( nurl_print `\n` )
            ( nurl_print `version:      ` ) ( nurl_print ( string_data . m version ) ) ( nurl_print `\n` )
            ? > ( string_len . m description ) 0 {
                ( nurl_print `description:  ` ) ( nurl_print ( string_data . m description ) ) ( nurl_print `\n` )
            } {}
            ? > ( string_len . m license ) 0 {
                ( nurl_print `license:      ` ) ( nurl_print ( string_data . m license ) ) ( nurl_print `\n` )
            } {}
            : i nd ( vec_len [Dep] . m dependencies )
            ( nurl_print `dependencies: ` ) ( nurl_print ( nurl_str_int nd ) ) ( nurl_print `\n` )
            ( manifest_free m )
        }
    }
    ^ rc
}

// ── add / remove (manifest mutation) ────────────────────────────
//
// Surgical text-level edits to nurl.toml: preserves user formatting
// and comments. We do NOT round-trip through the TOML parser — that
// would drop comments and renormalise whitespace. The trade-off is
// that our edits are line-oriented: an inline-table spanning
// multiple lines (`name = {\n  path = "..."\n}`) isn't recognised
// for remove. v1 manifests use single-line entries, so this is
// acceptable; `cargo add`/`remove` make the same line-oriented
// trade-off.

// True iff `line`, after stripping leading spaces/tabs, starts with
// `[` (any section header — handles both `[dep]` and `[[package]]`).
@ __is_section_header String line → b {
    : s raw ( string_data line )
    : i n ( string_len line )
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_get raw k )
        ? | == c 32 == c 9 { = k + k 1 } { ^ == c 91 }
    }
    ^ F
}

// True iff `line` (trimmed) is exactly `[dependencies]`.
@ __is_dependencies_header String line → b {
    : String t ( string_trim line )
    : b out != 0 ( nurl_str_eq ( string_data t ) `[dependencies]` )
    ( string_free t )
    ^ out
}

// True iff `line` declares dependency `name` (i.e. trimmed line
// starts with `<name>` followed by whitespace and `=`). Matches
// the v1 single-line inline-table or bare-string form.
@ __dep_line_matches String line s name → b {
    : String t ( string_trim_start line )
    : s s ( string_data t )
    : i tlen ( string_len t )
    : i nlen ( nurl_str_len name )
    // Single exit so the trimmed copy is always freed (early `^`s here
    // used to leak one String per non-matching line on every add/remove).
    : ~ b out F
    : ~ b decided F
    ? < tlen + nlen 1 { = decided T } {}
    : ~ i k 0
    ~ & ! decided < k nlen {
        ? != ( nurl_str_get s k ) ( nurl_str_get name k ) { = decided T } {}
        = k + k 1
    }
    ? ! decided {
        // After matching `<name>`, skip whitespace and require `=`.
        : ~ i p nlen
        : ~ b scanning T
        ~ & scanning < p tlen {
            : i c ( nurl_str_get s p )
            ? | == c 32 == c 9 { = p + p 1 } {
                = out == c 61
                = scanning F
            }
        }
    } {}
    ( string_free t )
    ^ out
}

// Build the dependency value string. v1 forms:
//   * Both path and version → { path = "<P>", version = "<V>" }
//   * Path only             → { path = "<P>" }
//   * Version only          → "<V>"
//   * Neither               → "" (empty bare-string; useless but legal)
@ __dep_value_text s path s version → String {
    : i plen ( nurl_str_len path )
    : i vlen ( nurl_str_len version )
    : String out ( string_with_cap 64 )
    ? > plen 0 {
        ( string_push_str out `{ path = "` )
        ( string_push_str out path )
        ( string_push_str out `"` )
        ? > vlen 0 {
            ( string_push_str out `, version = "` )
            ( string_push_str out version )
            ( string_push_str out `"` )
        } {}
        ( string_push_str out ` }` )
    } {
        ( string_push_str out `"` )
        ? > vlen 0 { ( string_push_str out version ) } {}
        ( string_push_str out `"` )
    }
    ^ out
}

// Join a Vec[String] back into a single String with `\n` separators.
// Used to reassemble after line-oriented mutation.
@ __join_lines ( Vec String ) lines → String {
    : String out ( string_with_cap 256 )
    : i n ( vec_len [String] lines )
    : ~ i k 0
    ~ < k n {
        : ?String lk ( vec_get [String] lines k )
        ?? lk {
            T l → ( string_push_str out ( string_data l ) )
            F _ → {}
        }
        ? < k - n 1 { ( string_push_char out 10 ) } {}
        = k + k 1
    }
    ^ out
}

@ __cmd_add s name s path s version → i {
    ? == 0 ( nurl_str_len name ) {
        ( nurl_eprintln `nurlpkg: 'add' requires a package name` )
        ( nurl_eprintln `Usage: nurlpkg add <name> [--path <path>] [--version <version>]` )
        ^ 2
    } {}
    ? ! ( file_exists `nurl.toml` ) {
        ( nurl_eprintln `nurlpkg: no nurl.toml in the current directory` )
        ^ 1
    } {}
    : !String IoErr rr ( read_file `nurl.toml` )
    : ~ String src ( string_new )
    ?? rr {
        T s → {
            ( string_free src )
            = src s
        }
        F _ → {
            ( nurl_eprintln `nurlpkg: failed to read nurl.toml` )
            ^ 1
        }
    }
    : ( Vec String ) lines ( string_split src `\n` )
    ( string_free src )

    // First pass: locate the [dependencies] header. Also scan the
    // section for a duplicate <name> entry.
    : ~ i dep_hdr_idx -1
    : ~ i dep_end_idx -1
    : i nlines ( vec_len [String] lines )
    : ~ i k 0
    ~ < k nlines {
        : ?String lk ( vec_get [String] lines k )
        ?? lk {
            T line → {
                ? ( __is_dependencies_header line ) {
                    = dep_hdr_idx k
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ? >= dep_hdr_idx 0 {
        // Find the end of the [dependencies] section: the next
        // section header, or EOF.
        : ~ i p + dep_hdr_idx 1
        : ~ b done F
        ~ ! done {
            ? >= p nlines { = done T = dep_end_idx nlines } {
                : ?String lk ( vec_get [String] lines p )
                ?? lk {
                    T line → {
                        ? ( __is_section_header line ) {
                            = done T = dep_end_idx p
                        } { = p + p 1 }
                    }
                    F _ → = p + p 1
                }
            }
        }
        // Duplicate-name guard.
        : ~ i j + dep_hdr_idx 1
        ~ < j dep_end_idx {
            : ?String lk ( vec_get [String] lines j )
            ?? lk {
                T line → {
                    ? ( __dep_line_matches line name ) {
                        ( nurl_eprint `nurlpkg: '` )
                        ( nurl_eprint name )
                        ( nurl_eprintln `' is already declared under [dependencies]` )
                        ( nurl_eprintln `Run 'nurlpkg remove <name>' first.` )
                        : i fn ( vec_len [String] lines )
                        : ~ i fk 0
                        ~ < fk fn {
                            : ?String fpk ( vec_get [String] lines fk )
                            ?? fpk { T s → ( string_free s ) F _ → {} }
                            = fk + fk 1
                        }
                        ( vec_free [String] lines )
                        ^ 1
                    } {}
                }
                F _ → {}
            }
            = j + j 1
        }
    } {}

    // Build the new dependency line.
    : String value_text ( __dep_value_text path version )
    : String new_line ( string_from name )
    ( string_push_str new_line ` = ` )
    ( string_push_str new_line ( string_data value_text ) )
    ( string_free value_text )

    : ( Vec String ) out_lines ( vec_new [String] )
    ? >= dep_hdr_idx 0 {
        // Copy lines [0, dep_end_idx), then insert new_line, then
        // copy the rest.
        : ~ i j 0
        ~ < j dep_end_idx {
            : ?String lk ( vec_get [String] lines j )
            ?? lk {
                T line → ( vec_push [String] out_lines ( string_from ( string_data line ) ) )
                F _ → {}
            }
            = j + j 1
        }
        ( vec_push [String] out_lines new_line )
        ~ < j nlines {
            : ?String lk ( vec_get [String] lines j )
            ?? lk {
                T line → ( vec_push [String] out_lines ( string_from ( string_data line ) ) )
                F _ → {}
            }
            = j + j 1
        }
    } {
        // No [dependencies] section — append both header and entry.
        : ~ i j 0
        ~ < j nlines {
            : ?String lk ( vec_get [String] lines j )
            ?? lk {
                T line → ( vec_push [String] out_lines ( string_from ( string_data line ) ) )
                F _ → {}
            }
            = j + j 1
        }
        // Trailing blank line so the new section is visually
        // separated from whatever preceded it.
        ( vec_push [String] out_lines ( string_new ) )
        ( vec_push [String] out_lines ( string_from `[dependencies]` ) )
        ( vec_push [String] out_lines new_line )
    }
    // Free the input lines.
    : i fn ( vec_len [String] lines )
    : ~ i fk 0
    ~ < fk fn {
        : ?String fpk ( vec_get [String] lines fk )
        ?? fpk { T s → ( string_free s ) F _ → {} }
        = fk + fk 1
    }
    ( vec_free [String] lines )

    : String joined ( __join_lines out_lines )
    : i jfn ( vec_len [String] out_lines )
    : ~ i jfk 0
    ~ < jfk jfn {
        : ?String fpk ( vec_get [String] out_lines jfk )
        ?? fpk { T s → ( string_free s ) F _ → {} }
        = jfk + jfk 1
    }
    ( vec_free [String] out_lines )

    : !v IoErr wr ( write_file `nurl.toml` ( string_data joined ) )
    ( string_free joined )
    : ~ i rc 0
    ?? wr {
        T _ → {
            ( nurl_print `added '` )
            ( nurl_print name )
            ( nurl_print `' to [dependencies]\n` )
        }
        F _ → {
            ( nurl_eprintln `nurlpkg: failed to write nurl.toml` )
            = rc 1
        }
    }
    ^ rc
}

@ __cmd_remove s name → i {
    ? == 0 ( nurl_str_len name ) {
        ( nurl_eprintln `nurlpkg: 'remove' requires a package name` )
        ( nurl_eprintln `Usage: nurlpkg remove <name>` )
        ^ 2
    } {}
    ? ! ( file_exists `nurl.toml` ) {
        ( nurl_eprintln `nurlpkg: no nurl.toml in the current directory` )
        ^ 1
    } {}
    : !String IoErr rr ( read_file `nurl.toml` )
    : ~ String src ( string_new )
    ?? rr {
        T s → {
            ( string_free src )
            = src s
        }
        F _ → {
            ( nurl_eprintln `nurlpkg: failed to read nurl.toml` )
            ^ 1
        }
    }
    : ( Vec String ) lines ( string_split src `\n` )
    ( string_free src )

    : i nlines ( vec_len [String] lines )
    : ~ b in_deps F
    : ~ b removed F
    : ( Vec String ) out_lines ( vec_new [String] )
    : ~ i k 0
    ~ < k nlines {
        : ?String lk ( vec_get [String] lines k )
        ?? lk {
            T line → {
                ? ( __is_section_header line ) {
                    = in_deps ( __is_dependencies_header line )
                    ( vec_push [String] out_lines ( string_from ( string_data line ) ) )
                } {
                    ? in_deps {
                        ? ( __dep_line_matches line name ) {
                            = removed T
                            // Drop this line.
                        } {
                            ( vec_push [String] out_lines ( string_from ( string_data line ) ) )
                        }
                    } {
                        ( vec_push [String] out_lines ( string_from ( string_data line ) ) )
                    }
                }
            }
            F _ → {}
        }
        = k + k 1
    }
    // Free the input lines.
    : ~ i fk 0
    ~ < fk nlines {
        : ?String fpk ( vec_get [String] lines fk )
        ?? fpk { T s → ( string_free s ) F _ → {} }
        = fk + fk 1
    }
    ( vec_free [String] lines )

    ? ! removed {
        ( nurl_eprint `nurlpkg: '` )
        ( nurl_eprint name )
        ( nurl_eprintln `' is not declared under [dependencies]` )
        : i jfn ( vec_len [String] out_lines )
        : ~ i jfk 0
        ~ < jfk jfn {
            : ?String fpk ( vec_get [String] out_lines jfk )
            ?? fpk { T s → ( string_free s ) F _ → {} }
            = jfk + jfk 1
        }
        ( vec_free [String] out_lines )
        ^ 1
    } {}

    : String joined ( __join_lines out_lines )
    : i jfn ( vec_len [String] out_lines )
    : ~ i jfk 0
    ~ < jfk jfn {
        : ?String fpk ( vec_get [String] out_lines jfk )
        ?? fpk { T s → ( string_free s ) F _ → {} }
        = jfk + jfk 1
    }
    ( vec_free [String] out_lines )

    : !v IoErr wr ( write_file `nurl.toml` ( string_data joined ) )
    ( string_free joined )
    : ~ i rc 0
    ?? wr {
        T _ → {
            ( nurl_print `removed '` )
            ( nurl_print name )
            ( nurl_print `' from [dependencies]\n` )
        }
        F _ → {
            ( nurl_eprintln `nurlpkg: failed to write nurl.toml` )
            = rc 1
        }
    }
    ^ rc
}

// ── update (move dependency requirements to the newest versions) ─────
//
// `nurlpkg update [<name>…] [--all]` walks [dependencies] and offers to
// move each requirement onto the newest available version:
//
//   * registry dep → the newest non-yanked version in the registry index
//   * path dep     → the version in the dep's own local nurl.toml — that
//     is the code you build against, and the publish gate requires the
//     requirement to cover it (see __check_pathdep_drift); the registry
//     may not carry that version yet, so the index is the wrong oracle
//
// A requirement the newest version already satisfies is left untouched
// (`^0.2` already resolves to 0.2.5 — rewriting it to `^0.2.5` is churn).
// Each change is confirmed on stdin (y/N, default No); `--all` (aliases
// `-y` / `--yes`) accepts everything unattended. Edits are surgical and
// line-oriented like add/remove: only the version value on the dep's
// line changes, so `path = …` / `registry = …` keys, formatting and
// comments survive.

// Candidate "newest" version for one dependency; "" when unknown.
@ __update_candidate Manifest m Dep d → String {
    ? > ( string_len . d path ) 0 {
        // Path dep: the local copy is authoritative.
        : String mf ( string_from ( string_data . d path ) )
        ( string_push_str mf `/nurl.toml` )
        : !Manifest ManifestErr mr ( manifest_load ( string_data mf ) )
        ( string_free mf )
        ?? mr {
            T dm → {
                : String out ( string_from ( string_data . dm version ) )
                ( manifest_free dm )
                ^ out
            }
            F _ → ^ ( string_new )
        }
    } {}
    // Registry dep: newest non-yanked published version.
    : ~ String reg ( string_new )
    ? > ( string_len . d registry ) 0 {
        ( string_free reg )
        = reg ( string_from ( string_data . d registry ) )
    } {
        ( string_free reg )
        = reg ( __registry_url m )
    }
    : String body ( pkg_fetch_index ( string_data reg ) ( string_data . d name ) )
    ( string_free reg )
    : ~ String out ( string_new )
    ? > ( string_len body ) 0 {
        ?? ( regindex_parse ( string_data body ) ) {
            T idx → {
                : i sel ( regindex_select idx `*` )
                ? >= sel 0 {
                    : ?IdxVersion vo ( vec_get [IdxVersion] . idx versions sel )
                    ?? vo {
                        T v → {
                            ( string_free out )
                            = out ( string_from ( string_data . v version ) )
                        }
                        F → {}
                    }
                } {}
                ( regindex_free idx )
            }
            F _ → {}
        }
    } {}
    ( string_free body )
    ^ out
}

// True when `oldreq` already admits `ver` — nothing to update. An
// unparsable requirement or version conservatively returns F so the
// update is offered rather than silently suppressed.
@ __req_admits s oldreq s ver → b {
    ?? ( semver_req_parse oldreq ) {
        F _ → ^ F
        T req → {
            ?? ( semver_parse ver ) {
                F _ → {
                    ( semver_req_free req )
                    ^ F
                }
                T v → {
                    : b out ( semver_req_matches req v )
                    ( semver_free v )
                    ( semver_req_free req )
                    ^ out
                }
            }
        }
    }
}

// The new requirement, keeping the old one's operator style: `^`/`~`
// keep their operator, a bare pin stays a pin, and anything more exotic
// (ranges, comparators, `*`) becomes `^<ver>` — "newest compatible".
@ __styled_req s oldreq s ver → String {
    : ~ i op 94  // '^' — the default spelling
    : i n ( nurl_str_len oldreq )
    ? > n 0 {
        : i c0 ( nurl_str_get oldreq 0 )
        ? == c0 126 { = op 126 } {}  // keep '~'
        ? & >= c0 48 <= c0 57 { = op 0 } {}  // bare pin → bare pin
    } {}
    : String out ( string_with_cap + ( nurl_str_len ver ) 2 )
    ? != op 0 { ( string_push_char out op ) } {}
    ( string_push_str out ver )
    ^ out
}

// Replace the quoted version value on one dep line, both v1 forms:
//   name = "^0.2"                             → the value after `=`
//   name = { path = "..", version = "^0.2" }  → the version key's value
// Returns the rewritten line, or an empty String when the line has no
// version slot (a path-only inline table — nothing to rewrite).
@ __dep_line_set_version String line s newreq → String {
    : s raw ( string_data line )
    : i n ( string_len line )
    // Scan for the quoted value from `anchor`: after the `version` key
    // in an inline table, after `=` in the bare-string form.
    : ~ i anchor -1
    ? ( string_contains line `{` ) {
        : ?i vk ( string_index_of line `version` )
        ?? vk {
            T at → { = anchor + at 7 }
            F _ → {}
        }
    } {
        : ?i ek ( string_index_of line `=` )
        ?? ek {
            T at → { = anchor + at 1 }
            F _ → {}
        }
    }
    ? < anchor 0 { ^ ( string_new ) } {}
    : ~ i vstart -1
    : ~ i k anchor
    ~ & < k n < vstart 0 {
        ? == ( nurl_str_get raw k ) 34 { = vstart + k 1 } {}
        = k + k 1
    }
    ? < vstart 0 { ^ ( string_new ) } {}
    : ~ i vend vstart
    ~ & < vend n != ( nurl_str_get raw vend ) 34 { = vend + vend 1 }
    ? >= vend n { ^ ( string_new ) } {}
    : String out ( string_with_cap + n 16 )
    = k 0
    ~ < k vstart {
        ( string_push_char out ( nurl_str_get raw k ) )
        = k + k 1
    }
    ( string_push_str out newreq )
    = k vend
    ~ < k n {
        ( string_push_char out ( nurl_str_get raw k ) )
        = k + k 1
    }
    ^ out
}

// Rewrite dependency `name`'s requirement in ./nurl.toml to `newreq`,
// preserving everything else on the line. 0 = ok.
@ __rewrite_dep_req s name s newreq → i {
    : !String IoErr rr ( read_file `nurl.toml` )
    : ~ String src ( string_new )
    ?? rr {
        T s → {
            ( string_free src )
            = src s
        }
        F _ → {
            ( nurl_eprintln `nurlpkg: failed to read nurl.toml` )
            ^ 1
        }
    }
    : ( Vec String ) lines ( string_split src `\n` )
    ( string_free src )
    : i nlines ( vec_len [String] lines )
    : ( Vec String ) out_lines ( vec_new [String] )
    : ~ b in_deps F
    : ~ b done F
    : ~ i k 0
    ~ < k nlines {
        : ?String lk ( vec_get [String] lines k )
        ?? lk {
            T line → {
                ? ( __is_section_header line ) {
                    = in_deps ( __is_dependencies_header line )
                } {}
                : ~ b copied F
                ? & & in_deps ! done ( __dep_line_matches line name ) {
                    : String nl ( __dep_line_set_version line newreq )
                    ? > ( string_len nl ) 0 {
                        ( vec_push [String] out_lines nl )
                        = copied T
                        = done T
                    } { ( string_free nl ) }
                } {}
                ? ! copied {
                    ( vec_push [String] out_lines ( string_from ( string_data line ) ) )
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    : ~ i fk 0
    ~ < fk nlines {
        : ?String fpk ( vec_get [String] lines fk )
        ?? fpk {
            T s → ( string_free s )
            F _ → {}
        }
        = fk + fk 1
    }
    ( vec_free [String] lines )
    : ~ i rc 0
    ? done {
        : String joined ( __join_lines out_lines )
        : !v IoErr wr ( write_file `nurl.toml` ( string_data joined ) )
        ( string_free joined )
        ?? wr {
            T _ → {}
            F _ → {
                ( nurl_eprintln `nurlpkg: failed to write nurl.toml` )
                = rc 1
            }
        }
    } {
        ( nurl_eprint `nurlpkg: could not rewrite '` )
        ( nurl_eprint name )
        ( nurl_eprintln `' in nurl.toml` )
        = rc 1
    }
    : i jn ( vec_len [String] out_lines )
    : ~ i jk 0
    ~ < jk jn {
        : ?String fpk ( vec_get [String] out_lines jk )
        ?? fpk {
            T s → ( string_free s )
            F _ → {}
        }
        = jk + jk 1
    }
    ( vec_free [String] out_lines )
    ^ rc
}

// One y/N confirmation on stdin. Anything but y/yes is a no — and so is
// EOF (piped stdin), so a scripted run without --all never mutates.
@ __confirm_update s name s oldreq s newreq → b {
    ( nurl_print `update '` )
    ( nurl_print name )
    ( nurl_print `' ` )
    ( nurl_print oldreq )
    ( nurl_print ` -> ` )
    ( nurl_print newreq )
    ( nurl_print `? [y/N] ` )
    ( flush )
    : String ans ( read_line )
    : String t ( string_trim ans )
    ( string_free ans )
    : String lo ( string_to_lower t )
    ( string_free t )
    : b yes | != 0 ( nurl_str_eq ( string_data lo ) `y` ) != 0 ( nurl_str_eq ( string_data lo ) `yes` )
    ( string_free lo )
    ^ yes
}

@ __cmd_update ( Vec String ) only i all → i {
    ? ! ( file_exists `nurl.toml` ) {
        ( nurl_eprintln `nurlpkg: no nurl.toml in the current directory (run 'nurlpkg init <name>' first)` )
        ^ 1
    } {}
    : !Manifest ManifestErr mr ( manifest_load `nurl.toml` )
    ?? mr {
        F e → {
            ( nurl_eprint `nurlpkg: failed to parse nurl.toml (` )
            ( nurl_eprint ( manifest_err_name e ) )
            ( nurl_eprintln `)` )
            ^ 1
        }
        T m → {
            : i n ( vec_len [Dep] . m dependencies )
            ? == n 0 {
                ( nurl_print `no dependencies in nurl.toml\n` )
                ( manifest_free m )
                ^ 0
            } {}
            : ~ i changed 0
            : ~ i failed 0
            // Explicitly named packages must actually be dependencies —
            // a typo silently updating nothing would read as "up to date".
            : i onlyn ( vec_len [String] only )
            : ~ i ok 0
            ~ < ok onlyn {
                : ?String oo ( vec_get [String] only ok )
                ?? oo {
                    T name → {
                        ? ( __manifest_has_dep m ( string_data name ) ) {} {
                            ( nurl_eprint `nurlpkg: '` )
                            ( nurl_eprint ( string_data name ) )
                            ( nurl_eprintln `' is not declared under [dependencies]` )
                            = failed + failed 1
                        }
                    }
                    F _ → {}
                }
                = ok + ok 1
            }
            : ~ i k 0
            ~ < k n {
                : ?Dep dk ( vec_get [Dep] . m dependencies k )
                ?? dk {
                    T d → {
                        : s dname ( string_data . d name )
                        : ~ b want T
                        ? > ( vec_len [String] only ) 0 { = want ( __vec_has_str only dname ) } {}
                        ? want {
                            ? == ( string_len . d version ) 0 {
                                ( nurl_print `  ` )
                                ( nurl_print dname )
                                ( nurl_print `: path-only (no version requirement) — skipped\n` )
                            } {
                                : String cand ( __update_candidate m d )
                                : s oldreq ( string_data . d version )
                                ? == ( string_len cand ) 0 {
                                    ( nurl_print `  ` )
                                    ( nurl_print dname )
                                    ( nurl_print `: no published version found — skipped\n` )
                                } {
                                    ? ( __req_admits oldreq ( string_data cand ) ) {
                                        ( nurl_print `  ` )
                                        ( nurl_print dname )
                                        ( nurl_print ` ` )
                                        ( nurl_print oldreq )
                                        ( nurl_print ` — up to date (newest is ` )
                                        ( nurl_print ( string_data cand ) )
                                        ( nurl_print `)\n` )
                                    } {
                                        : String newreq ( __styled_req oldreq ( string_data cand ) )
                                        : ~ b go != 0 all
                                        ? == all 0 {
                                            = go ( __confirm_update dname oldreq ( string_data newreq ) )
                                        } {}
                                        ? go {
                                            ? == ( __rewrite_dep_req dname ( string_data newreq ) ) 0 {
                                                ( nurl_print `  ` )
                                                ( nurl_print dname )
                                                ( nurl_print `: ` )
                                                ( nurl_print oldreq )
                                                ( nurl_print ` -> ` )
                                                ( nurl_print ( string_data newreq ) )
                                                ( nurl_print `\n` )
                                                = changed + changed 1
                                            } { = failed + failed 1 }
                                        } {
                                            ( nurl_print `  ` )
                                            ( nurl_print dname )
                                            ( nurl_print `: skipped\n` )
                                        }
                                        ( string_free newreq )
                                    }
                                }
                                ( string_free cand )
                            }
                        } {}
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ( manifest_free m )
            ? > changed 0 {
                ( nurl_print `updated ` )
                ( nurl_print ( nurl_str_int changed ) )
                ( nurl_print ` requirement(s) in nurl.toml — run 'nurlpkg install' to refresh deps/ and nurl.lock\n` )
            } {
                ( nurl_print `nothing updated\n` )
            }
            ^ ? > failed 0 1 0
        }
    }
}

// ── install ─────────────────────────────────────────────────────
//
// Walks the manifest, validates each path-dependency, then creates
// a symlink at `./deps/<name>` pointing at the resolved target
// directory. Transitive deps follow via BFS — each newly-installed
// dep's `nurl.toml` is loaded and its own dependencies appended to
// the queue. Cycles and diamond dependencies are deduplicated by
// the absolute target path (a `Vec[String]` "visited" set; v1
// scope, replace with a hash set when this becomes a hot path).

// Compose an absolute path from `(base, relpath)`. If `relpath`
// already starts with `/`, it's returned verbatim. Otherwise the
// two are joined with a single `/` separator. NB: this does NOT
// normalise `..` segments — the kernel resolves them at symlink
// dereference time, which is fine for build inputs.
@ __abs_join s base s relpath → String {
    : i rlen ( nurl_str_len relpath )
    ? > rlen 0 {
        ? == ( nurl_str_get relpath 0 ) 47 {
            ^ ( string_from relpath )
        } {}
    } {}
    : String out ( string_from base )
    : i blen ( string_len out )
    ? > blen 0 {
        ? != ( nurl_str_get ( string_data out ) - blen 1 ) 47 {
            ( string_push_char out 47 )
        } {}
    } { ( string_push_char out 47 ) }
    ( string_push_str out relpath )
    ^ out
}

// Compose `<dir>/<name>` for a deps-directory entry.
@ __deps_path s name → String {
    : String out ( string_from `deps/` )
    ( string_push_str out name )
    ^ out
}

// True if `target/nurl.toml` exists (i.e. the dep dir looks like
// a NURL package). The caller already knows `target` resolved —
// this is only the manifest-presence sanity check.
@ __dep_has_manifest s target → b {
    : String probe ( string_from target )
    : i tlen ( string_len probe )
    ? > tlen 0 {
        ? != ( nurl_str_get ( string_data probe ) - tlen 1 ) 47 {
            ( string_push_char probe 47 )
        } {}
    } { ( string_push_char probe 47 ) }
    ( string_push_str probe `nurl.toml` )
    : b ok ( file_exists ( string_data probe ) )
    ( string_free probe )
    ^ ok
}

// Linear search; v1 scope (n is small).
@ __seen_contains ( Vec String ) seen s needle → b {
    : i n ( vec_len [String] seen )
    : ~ i k 0
    ~ < k n {
        : ?String sk ( vec_get [String] seen k )
        ?? sk {
            T s → {
                ? != 0 ( nurl_str_eq ( string_data s ) needle ) { ^ T } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ F
}

// Process one Dep:
//   * skip with warning if `path` is empty (registry / bare-version)
//   * resolve absolute target via __abs_join
//   * dedup against `seen`; skip silently if already installed
//   * verify target/nurl.toml exists; warn + skip otherwise
//   * symlink deps/<name> → target (refusing to overwrite)
//   * append target to `seen`, append target's own deps to `queue`
//
// Returns 0 on success (including silent dedup / clean skip), 1 on
// any user-visible failure for this dep.
@ __install_one s cwd Dep d ( Vec String ) seen ( Vec String ) queue → i {
    : s name ( string_data . d name )
    : s relpath ( string_data . d path )
    ? == 0 ( string_len . d path ) {
        // Registry dep — resolved + installed by the registry pass
        // (__install_registry), not the path-dep BFS. Skip silently here.
        ^ 0
    } {}
    : String target ( __abs_join cwd relpath )
    : s target_s ( string_data target )
    ? ( __seen_contains seen target_s ) {
        ( string_free target )
        ^ 0
    } {}
    ? ! ( __dep_has_manifest target_s ) {
        // Local path absent. If the dep also carries a registry version
        // (`{ path, version }` hybrid), the registry pass will fetch it —
        // not an error. Otherwise it's a genuinely missing local dep.
        ? ( dep_has_version d ) {
            ( nurl_print `  ` ) ( nurl_print name )
            ( nurl_print ` (local path absent; resolving from registry)\n` )
            ( string_free target )
            ^ 0
        } {}
        ( nurl_eprint `  ` )
        ( nurl_eprint name )
        ( nurl_eprint `: skip (no nurl.toml at ` )
        ( nurl_eprint target_s )
        ( nurl_eprintln `)` )
        ( string_free target )
        ^ 1
    } {}
    : String linkpath ( __deps_path name )
    : s linkpath_s ( string_data linkpath )
    ? ( file_exists linkpath_s ) {
        // An entry already exists. Use readlink(2) to confirm it's a
        // symlink pointing where we expect — a mismatch means a name
        // collision across transitive deps (two different targets want
        // the same `deps/<name>` slot), which we surface as an error.
        // A non-symlink entry (readlink → EINVAL) falls back to the v1
        // idempotent behaviour: treat it as already-installed.
        : ~ i existing_rc 0
        : !String IoErr rl ( fs_readlink linkpath_s )
        ?? rl {
            T existing → {
                ? != 0 ( nurl_str_eq ( string_data existing ) target_s ) {
                    ( nurl_print `  ` ) ( nurl_print name )
                    ( nurl_print ` (already installed, verified)\n` )
                } {
                    ( nurl_eprint `  ` ) ( nurl_eprint name )
                    ( nurl_eprint `: existing link points to ` )
                    ( nurl_eprint ( string_data existing ) )
                    ( nurl_eprint ` not ` )
                    ( nurl_eprintln target_s )
                    = existing_rc 1
                }
                ( string_free existing )
            }
            F _ → {
                ( nurl_print `  ` ) ( nurl_print name )
                ( nurl_print ` (already installed)\n` )
            }
        }
        // Record it as seen so the transitive walker doesn't try
        // to re-process the same target.
        ( vec_push [String] seen ( string_from target_s ) )
        ( string_free linkpath )
        ( string_free target )
        ^ existing_rc
    } {}
    : !v IoErr sr ( fs_symlink target_s linkpath_s )
    : ~ i rc 0
    ?? sr {
        T _ → {
            ( nurl_print `  ` ) ( nurl_print name )
            ( nurl_print ` -> ` ) ( nurl_print target_s ) ( nurl_print `\n` )
            ( vec_push [String] seen ( string_from target_s ) )
            ( vec_push [String] queue ( string_from target_s ) )
        }
        F _ → {
            ( nurl_eprint `  ` ) ( nurl_eprint name )
            ( nurl_eprintln `: failed to create symlink` )
            = rc 1
        }
    }
    ( string_free linkpath )
    ( string_free target )
    ^ rc
}

// Read the manifest at `<dir>/nurl.toml` and append each of its
// dependencies to `queue` (for transitive walk). Returns 0 on
// success, 1 if the manifest couldn't be read or parsed. Each
// queued entry carries the *root* deps/ relative to `cwd`, since
// `__install_one` always installs into the top-level project's
// `deps/`.
@ __enqueue_transitive s base_dir s cwd ( Vec Dep ) out → i {
    : String mf ( string_from base_dir )
    : i blen ( string_len mf )
    ? > blen 0 {
        ? != ( nurl_str_get ( string_data mf ) - blen 1 ) 47 {
            ( string_push_char mf 47 )
        } {}
    } { ( string_push_char mf 47 ) }
    ( string_push_str mf `nurl.toml` )
    : !Manifest ManifestErr mr ( manifest_load ( string_data mf ) )
    ( string_free mf )
    : ~ i rc 0
    ?? mr {
        F e → {
            ( nurl_eprint `  warning: failed to parse ` )
            ( nurl_eprint base_dir )
            ( nurl_eprint `/nurl.toml (` )
            ( nurl_eprint ( manifest_err_name e ) )
            ( nurl_eprintln `)` )
            = rc 1
        }
        T sub → {
            // Re-anchor each transitive dep's path against base_dir
            // (so a sibling-relative `path = "../foo"` resolves
            // against the sub-package, not against the project root).
            : i n ( vec_len [Dep] . sub dependencies )
            : ~ i k 0
            ~ < k n {
                : ?Dep dk ( vec_get [Dep] . sub dependencies k )
                ?? dk {
                    T d → {
                        ? > ( string_len . d path ) 0 {
                            : String new_path ( __abs_join base_dir ( string_data . d path ) )
                            : Dep dn @ Dep {
                                ( string_from ( string_data . d name ) )
                                new_path
                                ( string_from ( string_data . d version ) )
                                ( string_from ( string_data . d registry ) )
                            }
                            ( vec_push [Dep] out dn )
                        } {}
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ( manifest_free sub )
        }
    }
    ^ rc
}

// ── lockfile ────────────────────────────────────────────────────
//
// `nurl.lock` is a Cargo-shaped lockfile: one [[package]] block per
// resolved dependency. We regenerate from the actual on-disk `deps/`
// tree (resolved symlinks → manifests), so the lockfile is a pure
// "snapshot of current install state" rather than a separate state
// machine. Entries are sorted alphabetically by package name for
// deterministic diffs.

// Append `name = "<value>"` to `out`. Values are NOT escaped — TOML's
// basic-string escape rules apply (\\, \", \n, \t, \r). v1: the
// fields we write (name, version, source) come from manifests that
// already passed our own parser, and source paths are filesystem
// paths that on POSIX cannot contain " or \. If a Windows port lands
// or someone hand-crafts a manifest with quoted strings, this needs
// proper escaping.
@ __lock_kv_str String out s key s value → v {
    ( string_push_str out key )
    ( string_push_str out ` = "` )
    ( string_push_str out value )
    ( string_push_str out `"\n` )
}

// Write the lockfile by walking deps/. Returns 0 on success, 1 on
// any I/O failure. Missing deps/ is treated as an empty install →
// writes an empty lockfile (so a project with zero deps still gets
// a tracked file for reproducibility).
@ __write_lockfile ( Vec LockPkg ) regpkgs → i {
    : ( Vec String ) names ( vec_new [String] )
    ? ( file_exists `deps` ) {
        : !( Vec String ) IoErr lr ( dir_list `deps` )
        ?? lr {
            T entries → {
                : i n ( vec_len [String] entries )
                : ~ i k 0
                ~ < k n {
                    : ?String ek ( vec_get [String] entries k )
                    ?? ek {
                        T name → ( vec_push [String] names ( string_from ( string_data name ) ) )
                        F _ → {}
                    }
                    = k + k 1
                }
                : i fn ( vec_len [String] entries )
                : ~ i fk 0
                ~ < fk fn {
                    : ?String pk ( vec_get [String] entries fk )
                    ?? pk { T s → ( string_free s ) F _ → {} }
                    = fk + fk 1
                }
                ( vec_free [String] entries )
            }
            F _ → {
                ( nurl_eprintln `nurlpkg: failed to list deps/ directory while writing lockfile` )
                ( vec_free [String] names )
                ^ 1
            }
        }
    } {}
    ( sort_by [String] names \ String a String b → i { ^ ( cmp_string a b ) } )

    : String body ( string_with_cap 512 )
    ( string_push_str body `# nurl.lock — generated by nurlpkg.\n` )
    ( string_push_str body `# Do not edit this file by hand.\n` )
    ( string_push_str body `version = 1\n` )

    : i nn ( vec_len [String] names )
    : ~ i j 0
    ~ < j nn {
        : ?String nk ( vec_get [String] names j )
        ?? nk {
            T name → {
                // Read deps/<name>/nurl.toml — go through the symlink
                // transparently. If the target has no manifest, skip
                // silently (install would have warned about it).
                : String mfpath ( string_from `deps/` )
                ( string_push_str mfpath ( string_data name ) )
                ( string_push_str mfpath `/nurl.toml` )
                ? ( file_exists ( string_data mfpath ) ) {
                    : !Manifest ManifestErr mr ( manifest_load ( string_data mfpath ) )
                    ?? mr {
                        T m → {
                            ( string_push_str body `\n[[package]]\n` )
                            ( __lock_kv_str body `name` ( string_data . m name ) )
                            ( __lock_kv_str body `version` ( string_data . m version ) )
                            : i ridx ( __reg_lookup regpkgs ( string_data . m name ) )
                            ? >= ridx 0 {
                                // Registry dep: pin the registry source +
                                // tarball checksum from resolution.
                                : ?LockPkg rpo ( vec_get [LockPkg] regpkgs ridx )
                                ?? rpo {
                                    T rp → {
                                        ( __lock_kv_str body `source` ( string_data . rp source ) )
                                        ? > ( string_len . rp checksum ) 0 {
                                            ( __lock_kv_str body `checksum` ( string_data . rp checksum ) )
                                        } {}
                                    }
                                    F → {}
                                }
                            } {
                                // Path dep: source is the local deps/ entry.
                                : String src ( string_from `deps/` )
                                ( string_push_str src ( string_data name ) )
                                ( __lock_kv_str body `source` ( string_data src ) )
                                ( string_free src )
                            }
                            ( manifest_free m )
                        }
                        F _ → {
                            // Manifest reachable through the symlink
                            // but unparseable. Skip the entry.
                            ( nurl_eprint `  warning: deps/` )
                            ( nurl_eprint ( string_data name ) )
                            ( nurl_eprintln `/nurl.toml is unparseable — omitted from lockfile` )
                        }
                    }
                } {}
                ( string_free mfpath )
            }
            F _ → {}
        }
        = j + j 1
    }

    : !v IoErr wr ( write_file `nurl.lock` ( string_data body ) )
    ( string_free body )
    : ~ i nfree 0
    ~ < nfree nn {
        : ?String pk ( vec_get [String] names nfree )
        ?? pk { T s → ( string_free s ) F _ → {} }
        = nfree + nfree 1
    }
    ( vec_free [String] names )
    : ~ i rc 0
    ?? wr {
        T _ → {}
        F _ → {
            ( nurl_eprintln `nurlpkg: failed to write nurl.lock` )
            = rc 1
        }
    }
    ^ rc
}

// ── verify ──────────────────────────────────────────────────────
//
// Drift detection between `nurl.lock` and the current `deps/` tree.
// Reports each kind of mismatch and exits 1 if any are present. This
// is the CI-grade "is the install reproducible from the lockfile"
// check; intentionally does NOT mutate anything.

// Pull a string field out of a [[package]] TomlValue (TTable). Returns
// empty String if the field is missing or non-string.
@ __pkg_field_str TomlValue pkg s key → String {
    : ?TomlValue v ( toml_get pkg key )
    ?? v {
        T tv → {
            : ?String sv ( toml_as_str tv )
            ?? sv {
                T s → ^ s
                F empty → { ( string_free empty ) ^ ( string_new ) }
            }
        }
        F _ → {}
    }
    ^ ( string_new )
}

@ __cmd_verify → i {
    ? ! ( file_exists `nurl.lock` ) {
        ( nurl_eprintln `nurlpkg: no nurl.lock (run 'nurlpkg install' first)` )
        ^ 1
    } {}
    : s lock_src ( nurl_read_file `nurl.lock` )
    ? == 0 ( nurl_str_len lock_src ) {
        ( nurl_eprintln `nurlpkg: failed to read nurl.lock` )
        ^ 1
    } {}
    : !TomlValue TomlErr tr ( toml_parse lock_src )
    : ~ i rc 0
    ?? tr {
        F _ → {
            ( nurl_eprintln `nurlpkg: nurl.lock is not valid TOML` )
            = rc 1
        }
        T root → {
            // Collect expected names from [[package]] entries; check
            // version-drift inline against deps/<name>/nurl.toml.
            : ( Vec String ) expected ( vec_new [String] )
            : ?TomlValue pkgs ( toml_get root `package` )
            ?? pkgs {
                T pv → {
                    ?? pv {
                        TArr arr → {
                            : i np ( vec_len [TomlValue] arr )
                            : ~ i k 0
                            ~ < k np {
                                : ?TomlValue pe ( vec_get [TomlValue] arr k )
                                ?? pe {
                                    T pkg → {
                                        : String name ( __pkg_field_str pkg `name` )
                                        : String lock_ver ( __pkg_field_str pkg `version` )
                                        ? > ( string_len name ) 0 {
                                            : String mfpath ( string_from `deps/` )
                                            ( string_push_str mfpath ( string_data name ) )
                                            ( string_push_str mfpath `/nurl.toml` )
                                            ? ( file_exists ( string_data mfpath ) ) {
                                                : !Manifest ManifestErr mr ( manifest_load ( string_data mfpath ) )
                                                ?? mr {
                                                    T m → {
                                                        ? & > ( string_len lock_ver ) 0 == 0 ( nurl_str_eq ( string_data lock_ver ) ( string_data . m version ) ) {
                                                            ( nurl_eprint `  version drift: ` )
                                                            ( nurl_eprint ( string_data name ) )
                                                            ( nurl_eprint ` lock=` )
                                                            ( nurl_eprint ( string_data lock_ver ) )
                                                            ( nurl_eprint ` deps=` )
                                                            ( nurl_eprint ( string_data . m version ) )
                                                            ( nurl_eprintln `` )
                                                            = rc 1
                                                        } {}
                                                        ( manifest_free m )
                                                    }
                                                    F _ → {}
                                                }
                                            } {}
                                            ( string_free mfpath )
                                            ( vec_push [String] expected name )
                                        } { ( string_free name ) }
                                        ( string_free lock_ver )
                                    }
                                    F _ → {}
                                }
                                = k + k 1
                            }
                        }
                        _ → {}
                    }
                }
                F _ → {}
            }

            // Collect actual entries from deps/.
            : ( Vec String ) actual ( vec_new [String] )
            ? ( file_exists `deps` ) {
                : !( Vec String ) IoErr dr ( dir_list `deps` )
                ?? dr {
                    T entries → {
                        : i na ( vec_len [String] entries )
                        : ~ i k 0
                        ~ < k na {
                            : ?String ek ( vec_get [String] entries k )
                            ?? ek {
                                T n → ( vec_push [String] actual ( string_from ( string_data n ) ) )
                                F _ → {}
                            }
                            = k + k 1
                        }
                        : i fn ( vec_len [String] entries )
                        : ~ i fk 0
                        ~ < fk fn {
                            : ?String pk ( vec_get [String] entries fk )
                            ?? pk { T s → ( string_free s ) F _ → {} }
                            = fk + fk 1
                        }
                        ( vec_free [String] entries )
                    }
                    F _ → {}
                }
            } {}

            // Missing: expected ∖ actual.
            : i ne ( vec_len [String] expected )
            : ~ i j 0
            ~ < j ne {
                : ?String ek ( vec_get [String] expected j )
                ?? ek {
                    T name → {
                        ? ! ( __seen_contains actual ( string_data name ) ) {
                            ( nurl_eprint `  missing: ` )
                            ( nurl_eprint ( string_data name ) )
                            ( nurl_eprintln ` (in lockfile but not in deps/)` )
                            = rc 1
                        } {}
                    }
                    F _ → {}
                }
                = j + j 1
            }

            // Unexpected: actual ∖ expected.
            : i na ( vec_len [String] actual )
            : ~ i ja 0
            ~ < ja na {
                : ?String ak ( vec_get [String] actual ja )
                ?? ak {
                    T name → {
                        ? ! ( __seen_contains expected ( string_data name ) ) {
                            ( nurl_eprint `  unexpected: ` )
                            ( nurl_eprint ( string_data name ) )
                            ( nurl_eprintln ` (in deps/ but not in lockfile)` )
                            = rc 1
                        } {}
                    }
                    F _ → {}
                }
                = ja + ja 1
            }

            // Tidy up.
            : ~ i fk 0
            ~ < fk ne {
                : ?String pk ( vec_get [String] expected fk )
                ?? pk { T s → ( string_free s ) F _ → {} }
                = fk + fk 1
            }
            ( vec_free [String] expected )
            : ~ i fa 0
            ~ < fa na {
                : ?String pk ( vec_get [String] actual fa )
                ?? pk { T s → ( string_free s ) F _ → {} }
                = fa + fa 1
            }
            ( vec_free [String] actual )
            ( toml_value_free root )
        }
    }
    ? == rc 0 { ( nurl_print `nurl.lock matches deps/\n` ) } {}
    ^ rc
}

@ __cmd_lock → i {
    ? ! ( file_exists `nurl.toml` ) {
        ( nurl_eprintln `nurlpkg: no nurl.toml in the current directory` )
        ^ 1
    } {}
    // `lock` regenerates from the on-disk deps/ tree only; it does not
    // re-resolve registry deps over the network, so registry checksums
    // come from `install`. Pass an empty registry set here.
    : ( Vec LockPkg ) empty ( vec_new [LockPkg] )
    : i rc ( __write_lockfile empty )
    ( lockpkgs_free empty )
    ? == rc 0 { ( nurl_print `wrote nurl.lock\n` ) } {}
    ^ rc
}

// Resolve + download + verify + unpack the registry dependencies of `m`
// into deps/<name>. Pushes a LockPkg (with source + tarball checksum) into
// `out` for each SUCCESSFULLY installed package, so the lockfile reflects
// exactly what landed on disk. Returns 0 on full success, 1 if resolution
// or any package install failed (so `nurlpkg install` exits non-zero).
@ __install_registry Manifest m s cwd ( Vec LockPkg ) out → i {
    : ( Vec Dep ) roots ( __registry_roots m cwd )
    ? == ( vec_len [Dep] roots ) 0 {
        ( __deps_free_vec roots )
        ^ 0
    } {}
    : String reg ( __registry_url m )
    ( nurl_print `resolving registry dependencies against ` )
    ( nurl_print ( string_data reg ) )
    ( nurl_print `\n` )
    : ( @ String s ) fetch \ s nm → String { ^ ( pkg_fetch_index ( string_data reg ) nm ) }
    : ~ i rc 0
    : !( Vec LockPkg ) ResolveErr rr ( resolve_registry roots ( string_data reg ) fetch )
    ?? rr {
        F e → {
            ( nurl_eprint `nurlpkg: registry resolution failed (` )
            ( nurl_eprint ( resolve_err_name e ) )
            ( nurl_eprintln `)` )
            = rc 1
        }
        T locked → {
            : i ln ( vec_len [LockPkg] locked )
            : ~ i k 0
            ~ < k ln {
                : ?LockPkg po ( vec_get [LockPkg] locked k )
                ?? po {
                    T p → {
                        : !i PkgFetchErr ir ( pkg_install_one ( string_data reg ) ( string_data . p name ) ( string_data . p version ) ( string_data . p checksum ) `deps` )
                        ?? ir {
                            T _ → {
                                ( nurl_print `  ` ) ( nurl_print ( string_data . p name ) )
                                ( nurl_print ` ` ) ( nurl_print ( string_data . p version ) )
                                ( nurl_print ` (registry)\n` )
                                ( vec_push [LockPkg] out ( lock_pkg_new
                                ( string_data . p name )
                                ( string_data . p version )
                                ( string_data . p source )
                                ( string_data . p checksum ) ) )
                            }
                            F fe → {
                                ( nurl_eprint `  ` ) ( nurl_eprint ( string_data . p name ) )
                                ( nurl_eprint `: ` ) ( nurl_eprintln ( pkg_err_name fe ) )
                                = rc 1
                            }
                        }
                    }
                    F → {}
                }
                = k + k 1
            }
            ( lockpkgs_free locked )
        }
    }
    ( string_free reg )
    ( __deps_free_vec roots )
    ^ rc
}

// ── login / logout ───────────────────────────────────────────────

// Read a secret from the terminal with echo off (termios on POSIX, console
// mode on Windows; falls back to echoed input on WASI / when stdin isn't a
// tty). The runtime prints the prompt to stderr and returns the entered
// line with the trailing newline stripped. Same builtin packages/psql uses
// for its password prompt.
& `c` @ nurl_read_password s prompt → s

@ __cmd_login → i {
    : String reg ( __reg_default )
    ( nurl_print `Registry: ` ) ( nurl_print ( string_data reg ) ) ( nurl_print `\n` )
    // Hidden entry: the pasted token must not echo to the screen.
    : String token ( string_from ( nurl_read_password `Paste a publish token (get one at <registry>/login): ` ) )
    : ~ i rc 0
    ? == ( string_len token ) 0 {
        ( nurl_eprintln `nurlpkg: empty token; aborted` )
        = rc 1
    } {
        : !v IoErr sr ( creds_set ( string_data reg ) ( string_data token ) )
        ?? sr {
            T _ → {
                : String p ( creds_path )
                ( nurl_print `Saved token to ` ) ( nurl_print ( string_data p ) ) ( nurl_print `\n` )
                ( string_free p )
            }
            F _ → { ( nurl_eprintln `nurlpkg: failed to write credentials` ) = rc 1 }
        }
    }
    ( string_free token )
    ( string_free reg )
    ^ rc
}

@ __cmd_logout i revoke → i {
    : String reg ( __reg_default )
    : ~ i rc 0
    ? != revoke 0 {
        : String tok ( creds_get ( string_data reg ) )
        ? > ( string_len tok ) 0 {
            : !i PublishErr rr ( pkg_revoke ( string_data reg ) ( string_data tok ) )
            ?? rr {
                T _ → ( nurl_print `Revoked token server-side.\n` )
                F e → { ( nurl_eprint `nurlpkg: revoke failed (` ) ( nurl_eprint ( publish_err_name e ) ) ( nurl_eprintln `)` ) = rc 1 }
            }
        } { ( nurl_print `No stored token to revoke.\n` ) }
        ( string_free tok )
    } {}
    : !v IoErr cr ( creds_remove ( string_data reg ) )
    ?? cr {
        T _ → ( nurl_print `Removed local credential.\n` )
        F _ → { ( nurl_eprintln `nurlpkg: failed to update credentials` ) = rc 1 }
    }
    ( string_free reg )
    ^ rc
}

// ── search / info ────────────────────────────────────────────────

@ __cmd_search s query → i {
    : String reg ( __reg_default )
    : String body ( pkg_search ( string_data reg ) query )
    : ~ i rc 0
    ? == ( string_len body ) 0 {
        ( nurl_eprintln `nurlpkg: search failed (no response)` )
        = rc 1
    } {
        : !Json JsonError jr ( json_parse ( string_data body ) )
        ?? jr {
            F _ → { ( nurl_eprintln `nurlpkg: bad search response` ) = rc 1 }
            T root → {
                : ?Json ra ( json_obj_get root `results` )
                ?? ra {
                    T arr → {
                        : i n ( json_arr_len arr )
                        ? == n 0 { ( nurl_print `No matches.\n` ) } {}
                        : ~ i k 0
                        ~ < k n {
                            : ?Json eo ( json_arr_get arr k )
                            ?? eo {
                                T e → {
                                    : ?Json no ( json_obj_get e `name` )
                                    ?? no { T nm → ( nurl_print ( json_as_str nm ) ) F → {} }
                                    : ?Json vo ( json_obj_get e `version` )
                                    ?? vo { T vv → { ( nurl_print `  ` ) ( nurl_print ( json_as_str vv ) ) } F → {} }
                                    : ?Json dso ( json_obj_get e `description` )
                                    ?? dso {
                                        T dv → {
                                            ? & ( json_is_str dv ) > ( nurl_str_len ( json_as_str dv ) ) 0 {
                                                ( nurl_print `  — ` )
                                                ( nurl_print ( json_as_str dv ) )
                                            } {}
                                        }
                                        F → {}
                                    }
                                    ( nurl_print `\n` )
                                }
                                F → {}
                            }
                            = k + k 1
                        }
                    }
                    F → {}
                }
                ( json_free root )
            }
        }
    }
    ( string_free body )
    ( string_free reg )
    ^ rc
}

@ __cmd_registry_info s name → i {
    : String reg ( __reg_default )
    : String body ( pkg_fetch_index ( string_data reg ) name )
    : ~ i rc 0
    ? == ( string_len body ) 0 {
        ( nurl_eprint `nurlpkg: package not found: ` ) ( nurl_eprintln name )
        = rc 1
    } {
        : !RegIndex RegIndexErr ir ( regindex_parse ( string_data body ) )
        ?? ir {
            F _ → { ( nurl_eprintln `nurlpkg: bad index response` ) = rc 1 }
            T idx → {
                ( nurl_print ( string_data . idx name ) ) ( nurl_print `\nversions:\n` )
                : i n ( vec_len [IdxVersion] . idx versions )
                : ~ i k 0
                ~ < k n {
                    : ?IdxVersion vo ( vec_get [IdxVersion] . idx versions k )
                    ?? vo {
                        T v → {
                            ( nurl_print `  ` ) ( nurl_print ( string_data . v version ) )
                            ? . v yanked { ( nurl_print ` (yanked)` ) } {}
                            ( nurl_print `\n` )
                        }
                        F → {}
                    }
                    = k + k 1
                }
                ( regindex_free idx )
            }
        }
    }
    ( string_free body )
    ( string_free reg )
    ^ rc
}

// ── yank / unyank ────────────────────────────────────────────────

@ __cmd_yank s name s version i yank → i {
    : String reg ( __reg_default )
    : String token ( __resolve_token ( string_data reg ) )
    : ~ i rc 0
    ? == ( string_len token ) 0 {
        ( nurl_eprintln `nurlpkg: no auth token — run 'nurlpkg login' or set $NURL_TOKEN` )
        = rc 1
    } {
        : !i PublishErr yr ( pkg_yank ( string_data reg ) ( string_data token ) name version yank )
        ?? yr {
            T _ → {
                ( nurl_print ? != yank 0 `yanked ` `unyanked ` )
                ( nurl_print name ) ( nurl_print ` ` ) ( nurl_print version ) ( nurl_print `\n` )
            }
            F e → {
                ( nurl_eprint `nurlpkg: ` ) ( nurl_eprint ? != yank 0 `yank` `unyank` )
                ( nurl_eprint ` failed (` ) ( nurl_eprint ( publish_err_name e ) ) ( nurl_eprintln `)` )
                = rc 1
            }
        }
    }
    ( string_free token )
    ( string_free reg )
    ^ rc
}

// ── publish ─────────────────────────────────────────────────────
//
// Pack the current project into a .tar.gz and upload it to the registry's
// write endpoint. The token comes from $NURL_TOKEN or `nurlpkg login`; the
// registry from $NURL_REGISTRY → [package].registry → default.
// ── deps/ import audit (publish gate) ───────────────────────────────
//
// A source that imports `deps/<name>/…` needs `<name>` in
// [dependencies]: the symlink under deps/ is a LOCAL build artefact
// (nurlpkg materialises it from the manifest), so a missing declaration
// compiles fine on the author's machine and then fails for every user
// who installs from the registry with "cannot open deps/<name>/…".
// nurllama 0.1.0 shipped exactly that bug. Publishing now refuses it.

// Collect the package names appearing in `$ \`deps/<name>/…\`` imports
// across the package's .nu sources.
@ __scan_dep_imports → ( Vec String ) {
    : ( Vec String ) found ( vec_new [String] )
    : ( Vec String ) pats ( vec_new [String] )
    ( vec_push [String] pats ( string_from `src/*.nu` ) )
    ( vec_push [String] pats ( string_from `src/**/*.nu` ) )
    : ~ i pi 0
    ~ < pi ( vec_len [String] pats ) {
        ?? ( vec_get [String] pats pi ) {
            T pat → {
                ?? ( fs_glob ( string_data pat ) ) {
                    T files → {
                        : ~ i fi 0
                        ~ < fi ( vec_len [String] files ) {
                            ?? ( vec_get [String] files fi ) {
                                T f → { ( __scan_one_file ( string_data f ) found ) }
                                F → {}
                            }
                            = fi + fi 1
                        }
                        ( vec_free_with [String] files \ String x → v { ( string_free x ) } )
                    }
                    F _ → {}
                }
            }
            F → {}
        }
        = pi + pi 1
    }
    ( vec_free_with [String] pats \ String x → v { ( string_free x ) } )
    ^ found
}

// Append every `deps/<name>/` package name found in `path` to `acc`
// (deduplicated).
@ __scan_one_file s path ( Vec String ) acc → v {
    ?? ( read_file path ) {
        T txt → {
            : s src ( string_data txt )
            : i n ( nurl_str_len src )
            : ~ i i 0
            ~ < i n {
                // Only real imports count: `$` … backtick … "deps/<name>/".
                // Scanning for the bare literal would also match doc
                // comments (packages/http documents `deps/http/src/http.nu`
                // as its own usage line) — a false refusal.
                : ~ b is_import F
                // …and the `$` must START the line: packages/http's header
                // documents its own import as a COMMENT ("//     $ `deps/…`"),
                // which is not an import at all.
                : ~ b line_start T
                ? == ( nurl_str_get src i ) 36 {
                    : ~ i bk - i 1
                    ~ & >= bk 0 line_start {
                        : i cb ( nurl_str_get src bk )
                        ? == cb 10 { = bk -1 } {
                            ? | == cb 32 == cb 9 { = bk - bk 1 } { = line_start F }
                        }
                    }
                } {}
                ? & line_start == ( nurl_str_get src i ) 36 {
                    : ~ i q + i 1
                    ~ & < q n == ( nurl_str_get src q ) 32 { = q + q 1 }
                    ? & < q n == ( nurl_str_get src q ) 96 {
                        : i d0 + q 1
                        ? & < + d0 5 n & == ( nurl_str_get src d0 ) 100 & == ( nurl_str_get src + d0 1 ) 101
                        & == ( nurl_str_get src + d0 2 ) 112 & == ( nurl_str_get src + d0 3 ) 115 == ( nurl_str_get src + d0 4 ) 47 {
                            = is_import T
                            = i d0
                        } {}
                    } {}
                } {}
                ? is_import {
                    : ~ i j + i 5
                    : String nm ( string_new )
                    ~ & < j n != ( nurl_str_get src j ) 47 {
                        ( string_push_char nm ( nurl_str_get src j ) )
                        = j + j 1
                    }
                    ? & > ( string_len nm ) 0 < j n {
                        ? ( __vec_has_str acc ( string_data nm ) ) { ( string_free nm ) } { ( vec_push [String] acc nm ) }
                    } { ( string_free nm ) }
                    = i j
                } { = i + i 1 }
            }
            ( string_free txt )
        }
        F _ → {}
    }
}

@ __vec_has_str ( Vec String ) v s want → b {
    : ~ i k 0
    ~ < k ( vec_len [String] v ) {
        ?? ( vec_get [String] v k ) {
            T x → { ? ( nurl_str_eq ( string_data x ) want ) { ^ T } {} }
            F → {}
        }
        = k + k 1
    }
    ^ F
}

@ __manifest_has_dep Manifest m s want → b {
    : ~ i k 0
    ~ < k ( vec_len [Dep] . m dependencies ) {
        ?? ( vec_get [Dep] . m dependencies k ) {
            T d → { ? ( nurl_str_eq ( string_data . d name ) want ) { ^ T } {} }
            F → {}
        }
        = k + k 1
    }
    ^ F
}

// 0 = every deps/ import is declared; 1 = something is missing (message
// already printed).

// ── gate: does this package build against the RELEASED toolchain? ────
//
// A package's `$ `stdlib/…`` imports are resolved by whatever toolchain the
// USER has installed — not by the repo it was developed in. So a package that
// imports a stdlib file added since the last release publishes cleanly and then
// fails to install for everyone, with a `cannot open 'stdlib/std/fft.nu'` that
// points at the toolchain rather than at the package.
//
// That happened: packages/audio was published against a stdlib/std/fft.nu that
// only existed on main. The fix is not to remember — it is this gate. Every
// stdlib path a package imports must exist in the INSTALLED toolchain's stdlib
// ($NURL_STDLIB, or ~/.nurl/stdlib), and publishing is refused when one does
// not, with the release that is missing named.
//
// File existence is necessary and NOT sufficient, which the second half of
// this gate exists to catch. A package can import only stdlib files that have
// shipped for years and still call a FUNCTION added to one of them last week:
// pki-server 0.3.0 imports std/fs.nu and std/pkey.nu — both ancient — while
// calling `set_permissions` and `mldsa_priv_from_pem`, which the released
// stdlib does not define. Every path existed, the gate passed, and the tarball
// would have been unbuildable for every user of `nurlpkg install`. Publishing
// is irreversible, so the check has to be the real one: typecheck `src/main.nu`
// with the INSTALLED compiler against the INSTALLED stdlib, and believe it.
@ __scan_stdlib_imports_file s path ( Vec String ) acc → v {
    ?? ( read_file path ) {
        T txt → {
            : s src ( string_data txt )
            : i n ( nurl_str_len src )
            : ~ i i 0
            ~ < i n {
                // `$` at the start of a line, then a backtick, then "stdlib/"
                : ~ b at_line T
                ? == ( nurl_str_get src i ) 36 {
                    : ~ i bk - i 1
                    ~ & >= bk 0 at_line {
                        : i cb ( nurl_str_get src bk )
                        ? == cb 10 { = bk -1 } {
                            ? | == cb 32 == cb 9 { = bk - bk 1 } { = at_line F }
                        }
                    }
                } { = at_line F }
                ? & at_line == ( nurl_str_get src i ) 36 {
                    : ~ i q + i 1
                    ~ & < q n == ( nurl_str_get src q ) 32 { = q + q 1 }
                    ? & < q n == ( nurl_str_get src q ) 96 {
                        : i d0 + q 1
                        : String nm ( string_new )
                        : ~ i j d0
                        ~ & < j n != ( nurl_str_get src j ) 96 {
                            ( string_push_char nm ( nurl_str_get src j ) )
                            = j + j 1
                        }
                        ? != 0 ( nurl_str_starts ( string_data nm ) `stdlib/` ) {
                            ? ( __vec_has_str acc ( string_data nm ) ) { ( string_free nm ) }
                            { ( vec_push [String] acc nm ) }
                        } { ( string_free nm ) }
                        = i j
                    } {}
                } {}
                = i + i 1
            }
            ( string_free txt )
        }
        F _ → {}
    }
}

@ __scan_stdlib_imports → ( Vec String ) {
    : ( Vec String ) found ( vec_new [String] )
    : ( Vec String ) pats ( vec_new [String] )
    ( vec_push [String] pats ( string_from `src/*.nu` ) )
    ( vec_push [String] pats ( string_from `src/**/*.nu` ) )
    : ~ i pi 0
    ~ < pi ( vec_len [String] pats ) {
        ?? ( vec_get [String] pats pi ) {
            T pat → {
                ?? ( fs_glob ( string_data pat ) ) {
                    T files → {
                        : ~ i fi 0
                        ~ < fi ( vec_len [String] files ) {
                            ?? ( vec_get [String] files fi ) {
                                T f → { ( __scan_stdlib_imports_file ( string_data f ) found ) }
                                F → {}
                            }
                            = fi + fi 1
                        }
                        ( vec_free_with [String] files \ String x → v { ( string_free x ) } )
                    }
                    F _ → {}
                }
            }
            F → {}
        }
        = pi + pi 1
    }
    ( vec_free_with [String] pats \ String x → v { ( string_free x ) } )
    ^ found
}

// The stdlib the USER's toolchain will use: $NURL_STDLIB when set, else
// ~/.nurl (the installer's prefix).
@ __toolchain_stdlib_root → String {
    ?? ( env_get `NURL_STDLIB` ) {
        T v → {
            // an EMPTY NURL_STDLIB is not a stdlib — treat it as unset
            ? > ( string_len v ) 0 { ^ v } {}
            ( string_free v )
        }
        F → {}
    }
    ?? ( env_get `HOME` ) {
        T h → {
            : String p2 ( string_from ( string_data h ) )
            ( string_push_str p2 `/.nurl` )
            ( string_free h )
            ^ p2
        }
        F → {}
    }
    ^ ( string_new )
}

@ __check_stdlib_available → i {
    : String root ( __toolchain_stdlib_root )
    ? == 0 ( string_len root ) {
        ( string_free root )
        ^ 0
    } {}
    : ( Vec String ) used ( __scan_stdlib_imports )
    : ~ i missing 0
    : ~ i k 0
    ~ < k ( vec_len [String] used ) {
        ?? ( vec_get [String] used k ) {
            T rel → {
                : String full ( string_from ( string_data root ) )
                ( string_push_char full 47 )
                ( string_push_str full ( string_data rel ) )
                ? ( file_exists ( string_data full ) ) {} {
                    ? == missing 0 {
                        ( nurl_eprintln `nurlpkg: this package imports stdlib files that the INSTALLED toolchain does not have:` )
                    } {}
                    : String m ( string_from `  ` )
                    ( string_push_str m ( string_data rel ) )
                    ( nurl_eprintln ( string_data m ) )
                    ( string_free m )
                    = missing + missing 1
                }
                ( string_free full )
            }
            F → {}
        }
        = k + k 1
    }
    ( vec_free_with [String] used \ String x → v { ( string_free x ) } )
    ? > missing 0 {
        : String m ( string_from `nurlpkg: they exist in the repo but not in ` )
        ( string_push_str m ( string_data root ) )
        ( string_push_str m ` — so this package would publish cleanly and then fail to install for everyone. Cut a toolchain release that ships them first (or set NURL_STDLIB to the toolchain you are targeting).` )
        ( nurl_eprintln ( string_data m ) )
        ( string_free m )
    } {}
    ( string_free root )
    ^ ? > missing 0 1 0
}

// Typecheck the package's entry point with the toolchain the user will
// actually install with: front-end only, no link step (nurlc writes IR to
// stdout, which is discarded), so this needs no C toolchain and costs a
// fraction of a build.
//
// Which toolchain that is comes from __toolchain_stdlib_root — $NURL_STDLIB
// when set, else ~/.nurl. Pointing $NURL_STDLIB at a checkout therefore aims
// the gate at that checkout, which is the documented escape hatch for "I am
// publishing against this tree, not the release" and makes the check pass
// trivially. That is deliberate; the default, with $NURL_STDLIB unset, is the
// one that protects users.
//
// Two conditions leave the question unanswered rather than answered "yes":
// no compiler at <root>/bin/nurlc, and a compiler that will not launch. Both
// WARN on stderr and let the publish through — an unverifiable gate has to say
// so out loud rather than pass quietly, and refusing would make the tool
// unusable on a box that has no toolchain installed.
@ __installed_nurlc String root → String {
    : String p ( string_from ( string_data root ) )
    ( string_push_str p ? ( __is_windows ) `/bin/nurlc.exe` `/bin/nurlc` )
    ? ( file_exists ( string_data p ) ) { ^ p } {}
    ( string_free p )
    ^ ( string_new )
}

@ __check_builds_against_installed → i {
    ? ! ( file_exists `src/main.nu` ) { ^ 0 } {}
    : String root ( __toolchain_stdlib_root )
    ? == 0 ( string_len root ) { ( string_free root ) ^ 0 } {}

    : String cc ( __installed_nurlc root )
    ? == 0 ( string_len cc ) {
        ( nurl_eprint `nurlpkg: WARNING — no installed compiler at ` )
        ( nurl_eprint ( string_data root ) )
        ( nurl_eprintln `/bin/nurlc, so "does this build against the released toolchain?" went UNCHECKED.` )
        ( nurl_eprintln `nurlpkg:          Install the toolchain you are targeting before publishing.` )
        ( string_free cc )
        ( string_free root )
        ^ 0
    } {}

    : String cmd ( string_with_cap 160 )
    ( string_push_str cmd `NURL_STDLIB=` )
    ( string_push_str cmd ( string_data root ) )
    ( string_push_char cmd 32 )
    ( string_push_str cmd ( string_data cc ) )
    ( string_push_str cmd ` src/main.nu >/dev/null` )

    : ~ i bad 0
    ?? ( process_run_shell ( string_data cmd ) ) {
        T out → {
            ? ( output_success out ) {} {
                : s err ( output_stderr out )
                ( nurl_eprint `nurlpkg: this package does not compile against the INSTALLED toolchain at ` )
                ( nurl_eprintln ( string_data root ) )
                ( nurl_eprint err )
                // Two very different causes land here, and telling the
                // publisher the wrong one wastes their afternoon: an
                // unresolved deps/ tree is "run the build first", while
                // anything else is "the released stdlib is too old".
                ? > ( nurl_str_find err `cannot open import 'deps/` ) -1 {
                    ( nurl_eprintln `nurlpkg: deps/ is not resolved in this working tree — run 'nurlpkg build' (or link the` )
                    ( nurl_eprintln `nurlpkg: path deps) and try again. Nothing about the released toolchain was established.` )
                } {
                    ( nurl_eprintln `nurlpkg: every imported stdlib FILE exists there, but something the package calls does not.` )
                    ( nurl_eprintln `nurlpkg: publishing is irreversible, so this is refused — cut a toolchain release that ships` )
                    ( nurl_eprintln `nurlpkg: what this needs first, then publish.` )
                }
                = bad 1
            }
            ( output_free out )
        }
        F _ → {
            ( nurl_eprintln `nurlpkg: WARNING — could not launch the installed compiler; the released-toolchain build went UNCHECKED.` )
        }
    }
    ( string_free cmd )
    ( string_free cc )
    ( string_free root )
    ^ bad
}

@ __check_declared_deps Manifest m → i {
    : ( Vec String ) used ( __scan_dep_imports )
    : ~ i missing 0
    : ~ i k 0
    ~ < k ( vec_len [String] used ) {
        ?? ( vec_get [String] used k ) {
            T nm → {
                ? ( __manifest_has_dep m ( string_data nm ) ) {} {
                    ? == missing 0 {
                        ( nurl_eprintln `nurlpkg: sources import a package that is not declared in [dependencies]:` )
                    } {}
                    ( nurl_eprint `  deps/` )
                    ( nurl_eprint ( string_data nm ) )
                    ( nurl_eprint `/… is imported, but '` )
                    ( nurl_eprint ( string_data nm ) )
                    ( nurl_eprintln `' is missing from nurl.toml` )
                    = missing 1
                }
            }
            F → {}
        }
        = k + k 1
    }
    ( vec_free_with [String] used \ String x → v { ( string_free x ) } )
    ? != missing 0 {
        ( nurl_eprintln `  (the deps/ symlink is a local artefact — an undeclared dependency breaks every registry install)` )
    } {}
    ^ missing
}

// The cheap, network-free half of the same class: a path dep's VERSION
// REQUIREMENT must be satisfied by the LOCAL dependency's version. If the
// local http is 0.3.0 but the requirement says ^0.2, this package is built
// and tested against 0.3.0 here while every registry install compiles
// against 0.2.x — different code under the same publish. That is precisely
// how nurllama 0.1.1 shipped calling a function that existed only in the
// unpublished local http.
//
// 0 = every requirement covers its local dep; 1 = refuse (message printed).
@ __check_pathdep_req Manifest m → i {
    : ~ i bad 0
    : ~ i di 0
    ~ < di ( vec_len [Dep] . m dependencies ) {
        ?? ( vec_get [Dep] . m dependencies di ) {
            T d → {
                ? & ( dep_is_path d ) ( dep_has_version d ) {
                    : String dtoml ( string_from ( string_data . d path ) )
                    ( string_push_str dtoml `/nurl.toml` )
                    ?? ( manifest_load ( string_data dtoml ) ) {
                        T dm → {
                            ?? ( semver_req_parse ( string_data . d version ) ) {
                                T req → {
                                    ?? ( semver_parse ( string_data . dm version ) ) {
                                        T lv → {
                                            ? ( semver_req_matches req lv ) {} {
                                                ( nurl_eprint `nurlpkg: dependency '` )
                                                ( nurl_eprint ( string_data . dm name ) )
                                                ( nurl_eprint `' requires '` )
                                                ( nurl_eprint ( string_data . d version ) )
                                                ( nurl_eprint `' but the local copy is ` )
                                                ( nurl_eprintln ( string_data . dm version ) )
                                                ( nurl_eprintln `  You build against the local source; everyone else resolves the requirement from the registry — they would compile against different code. Widen the requirement (and publish that version) before publishing this package.` )
                                                = bad 1
                                            }
                                            ( semver_free lv )
                                        }
                                        F _ → {}
                                    }
                                    ( semver_req_free req )
                                }
                                F _ → {}
                            }
                            ( manifest_free dm )
                        }
                        F _ → {}
                    }
                    ( string_free dtoml )
                } {}
            }
            F → {}
        }
        = di + di 1
    }
    ^ bad
}

// ── path-dep drift audit (publish gate) ─────────────────────────────
//
// A path dependency with a version requirement is built LOCALLY here but
// resolved from the REGISTRY by everyone else. If the local copy has been
// edited without bumping its version, the two are different code under the
// same version number: the author's build succeeds and every registry
// install compiles against the old published source. That is exactly how
// nurllama 0.1.1 shipped calling http_app_stream — a function added to the
// local http package without republishing it.
//
// So: for every path dep whose version is already published, fetch that
// published tarball and compare its sources with the local ones. Any
// difference is refused, naming the dependency.

@ __srcs_of s dir → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : String pat ( string_from dir )
    ( string_push_str pat `/src/*.nu` )
    ?? ( fs_glob ( string_data pat ) ) {
        T fs → {
            : ~ i k 0
            ~ < k ( vec_len [String] fs ) {
                ?? ( vec_get [String] fs k ) {
                    T f → { ( vec_push [String] out ( string_from ( string_data f ) ) ) }
                    F → {}
                }
                = k + k 1
            }
            ( vec_free_with [String] fs \ String x → v { ( string_free x ) } )
        }
        F _ → {}
    }
    ( string_free pat )
    ^ out
}

// basename after the last '/'
@ __basename s p → String {
    : i n ( nurl_str_len p )
    : ~ i st 0
    : ~ i k 0
    ~ < k n {
        ? == ( nurl_str_get p k ) 47 { = st + k 1 } {}
        = k + k 1
    }
    : String out ( string_new )
    = k st
    ~ < k n {
        ( string_push_char out ( nurl_str_get p k ) )
        = k + k 1
    }
    ^ out
}

@ __files_same s a s b → b {
    ?? ( read_file_bytes a ) {
        T ba → {
            ?? ( read_file_bytes b ) {
                T bb → {
                    : b same ( bytes_eq ba bb )
                    ( vec_free [u] ba )
                    ( vec_free [u] bb )
                    ^ same
                }
                F _ → {
                    ( vec_free [u] ba )
                    ^ F
                }
            }
        }
        F _ → { ^ F }
    }
}

// 0 = no drift (or nothing to compare); 1 = refuse (message printed).
@ __check_pathdep_drift Manifest m s reg → i {
    : ~ i bad 0
    : ~ i di 0
    ~ < di ( vec_len [Dep] . m dependencies ) {
        ?? ( vec_get [Dep] . m dependencies di ) {
            T d → {
                ? & ( dep_is_path d ) ( dep_has_version d ) {
                    // local version of the dependency
                    : String dtoml ( string_from ( string_data . d path ) )
                    ( string_push_str dtoml `/nurl.toml` )
                    ?? ( manifest_load ( string_data dtoml ) ) {
                        T dm → {
                            : s dname ( string_data . dm name )
                            : s dver ( string_data . dm version )
                            : String idx ( pkg_fetch_index reg dname )
                            ? > ( string_len idx ) 0 {
                                ?? ( regindex_parse ( string_data idx ) ) {
                                    T ridx → {
                                        // is THIS local version already published?
                                        : ~ i hit -1
                                        : ~ i vi 0
                                        ~ < vi ( vec_len [IdxVersion] . ridx versions ) {
                                            ?? ( vec_get [IdxVersion] . ridx versions vi ) {
                                                T iv → {
                                                    ? ( nurl_str_eq ( string_data . iv version ) dver ) { = hit vi } {}
                                                }
                                                F → {}
                                            }
                                            = vi + vi 1
                                        }
                                        ? >= hit 0 {
                                            ?? ( vec_get [IdxVersion] . ridx versions hit ) {
                                                T iv → {
                                                    ? != 0 ( __dep_drifts reg dname ( string_data . iv version ) ( string_data . iv checksum ) ( string_data . d path ) ) {
                                                        ( nurl_eprint `nurlpkg: local '` )
                                                        ( nurl_eprint dname )
                                                        ( nurl_eprint `' differs from the published ` )
                                                        ( nurl_eprint dname )
                                                        ( nurl_eprint ` ` )
                                                        ( nurl_eprint dver )
                                                        ( nurl_eprintln ` — bump its version and publish it BEFORE publishing this package.` )
                                                        ( nurl_eprintln `  (a path dep is built locally here but fetched from the registry by everyone else)` )
                                                        = bad 1
                                                    } {}
                                                }
                                                F → {}
                                            }
                                        } {}
                                        ( regindex_free ridx )
                                    }
                                    F _ → {}
                                }
                            } {}
                            ( string_free idx )
                            ( manifest_free dm )
                        }
                        F _ → {}
                    }
                    ( string_free dtoml )
                } {}
            }
            F → {}
        }
        = di + di 1
    }
    ^ bad
}

// 1 = the published tarball's sources differ from the local ones.
@ __dep_drifts s reg s name s ver s checksum s localdir → i {
    : String troot ( __tmp_root )
    : String stage ( string_with_cap 96 )
    ( string_push_str stage ( string_data troot ) )
    ( string_push_str stage `/nurlpkg-drift-` )
    ( string_push_str stage name )
    ( string_free troot )
    ?? ( dir_remove_all ( string_data stage ) ) { T _ → {} F _ → {} }
    ?? ( dir_create_all ( string_data stage ) ) { T _ → {} F _ → {} }
    : !i PkgFetchErr fr ( pkg_install_one reg name ver checksum ( string_data stage ) )
    : ~ i drift 0
    ?? fr {
        F _ → {
            // cannot fetch/verify → do not block the publish on a network
            // failure; the undeclared-dep gate above still applies
            = drift 0
        }
        T _ → {
            : String pubdir ( string_with_cap 96 )
            ( string_push_str pubdir ( string_data stage ) )
            ( string_push_char pubdir 47 )
            ( string_push_str pubdir name )
            : ( Vec String ) locals ( __srcs_of localdir )
            : ( Vec String ) pubs ( __srcs_of ( string_data pubdir ) )
            ? != ( vec_len [String] locals ) ( vec_len [String] pubs ) { = drift 1 } {}
            : ~ i k 0
            ~ & < k ( vec_len [String] locals ) == drift 0 {
                ?? ( vec_get [String] locals k ) {
                    T lf → {
                        : String bn ( __basename ( string_data lf ) )
                        : String pf ( string_with_cap 96 )
                        ( string_push_str pf ( string_data pubdir ) )
                        ( string_push_str pf `/src/` )
                        ( string_push_str pf ( string_data bn ) )
                        ? ( __files_same ( string_data lf ) ( string_data pf ) ) {} { = drift 1 }
                        ( string_free pf )
                        ( string_free bn )
                    }
                    F → {}
                }
                = k + k 1
            }
            ( vec_free_with [String] locals \ String x → v { ( string_free x ) } )
            ( vec_free_with [String] pubs \ String x → v { ( string_free x ) } )
            ( string_free pubdir )
        }
    }
    ?? ( dir_remove_all ( string_data stage ) ) { T _ → {} F _ → {} }
    ( string_free stage )
    ^ drift
}

@ __cmd_publish b dry → i {
    ? ! ( file_exists `nurl.toml` ) {
        ( nurl_eprintln `nurlpkg: no nurl.toml in the current directory` )
        ^ 1
    } {}
    : !Manifest ManifestErr mr ( manifest_load `nurl.toml` )
    : ~ i rc 0
    ?? mr {
        F e → {
            ( nurl_eprint `nurlpkg: failed to parse nurl.toml (` )
            ( nurl_eprint ( manifest_err_name e ) )
            ( nurl_eprintln `)` )
            = rc 1
        }
        T m → {
            : String reg ( __registry_url m )
            : String token ( __resolve_token ( string_data reg ) )
            ? & ! dry == ( string_len token ) 0 {
                ( nurl_eprintln `nurlpkg: no auth token — run 'nurlpkg login' or set $NURL_TOKEN` )
                = rc 1
            } {
                ? != 0 ( __check_declared_deps m ) {
                    ( manifest_free m )
                    ^ 1
                } {}
                ? != 0 ( __check_stdlib_available ) {
                    ( manifest_free m )
                    ^ 1
                } {}
                ? != 0 ( __check_builds_against_installed ) {
                    ( manifest_free m )
                    ^ 1
                } {}
                ? != 0 ( __check_pathdep_req m ) {
                    ( manifest_free m )
                    ^ 1
                } {}
                ? != 0 ( __check_pathdep_drift m ( string_data reg ) ) {
                    ( manifest_free m )
                    ^ 1
                } {}
                : !( Vec u ) PackErr pr ( pkg_pack `.` )
                ?? pr {
                    F pe → {
                        ( nurl_eprint `nurlpkg: packaging failed (` )
                        ( nurl_eprint ( pack_err_name pe ) )
                        ( nurl_eprintln `)` )
                        = rc 1
                    }
                    T tarball → {
                        : ( Vec u ) digest ( sha256_pure tarball )
                        : String hex ( bytes_to_hex digest )
                        ( nurl_print ? dry `dry-run: would publish ` `publishing ` )
                        ( nurl_print ( string_data . m name ) )
                        ( nurl_print ` ` )
                        ( nurl_print ( string_data . m version ) )
                        ( nurl_print ` (` )
                        ( nurl_print ( nurl_str_int ( vec_len [u] tarball ) ) )
                        ( nurl_print ` bytes, sha256 ` )
                        ( nurl_print ( string_data hex ) )
                        ( nurl_print `)\nto ` )
                        ( nurl_print ( string_data reg ) )
                        ( nurl_print `\n` )
                        ? dry {
                            // What is IN the tarball, not just how big it is.
                            // The packer decides what counts as source, and a
                            // wrong answer in either direction used to look
                            // exactly like success.
                            ?? ( pkg_pack_list `.` ) {
                                T files → {
                                    ( nurl_print `dry-run: ` )
                                    ( nurl_print ( nurl_str_int ( vec_len [String] files ) ) )
                                    ( nurl_print ` files:\n` )
                                    : i fn ( vec_len [String] files )
                                    : ~ i fk 0
                                    ~ < fk fn {
                                        ?? ( vec_get [String] files fk ) {
                                            T fp → {
                                                ( nurl_print `  ` )
                                                ( nurl_print ( string_data fp ) )
                                                ( nurl_print `\n` )
                                            }
                                            F _ → {}
                                        }
                                        = fk + fk 1
                                    }
                                    ( vec_free_with [String] files \ String q → v { ( string_free q ) } )
                                }
                                F _ → {}
                            }
                            ( nurl_print `dry-run: every gate passed; nothing was uploaded.\n` )
                            ( vec_free [u] digest )
                            ( string_free hex )
                            ( vec_free [u] tarball )
                            ( string_free reg )
                            ( string_free token )
                            ( manifest_free m )
                            ^ 0
                        } {}
                        : String deps_json ( __deps_json m )
                        : !i PublishErr ur ( pkg_publish ( string_data reg ) ( string_data token ) tarball ( string_data . m name ) ( string_data . m version ) ( string_data deps_json ) )
                        ( string_free deps_json )
                        ?? ur {
                            T _ → ( nurl_print `published.\n` )
                            F ue → {
                                ?? ue {
                                    // 401: a real auth failure — tokens expire
                                    // after 90 days, the usual cause on a setup
                                    // that used to work.
                                    PubAuth → {
                                        ( nurl_eprintln `nurlpkg: publish failed (auth)` )
                                        ( nurl_eprintln `hint: registry tokens expire after 90 days - run 'nurlpkg login' to mint a fresh one` )
                                    }
                                    // 403: NOT auth. The registry refused the
                                    // name/version — point at the real causes
                                    // instead of sending them to re-login.
                                    PubForbidden → {
                                        ( nurl_eprintln `nurlpkg: publish forbidden (the registry refused this package)` )
                                        ( nurl_eprintln `hint: the name may be reserved, too similar to an existing package, or outside your token's package scope — it is NOT a token problem` )
                                    }
                                    PubConflict → {
                                        ( nurl_eprintln `nurlpkg: this version is already published (versions are immutable — bump the version)` )
                                    }
                                    // The upload got a connection but no reply.
                                    // Small requests (login, search, info) still
                                    // work, so this reads as "the registry is up
                                    // but publish is broken" — when the usual
                                    // cause is a network path that drops
                                    // full-size packets: a publish body is the
                                    // only request big enough to need them.
                                    PubTimeout → {
                                        ( nurl_eprintln `nurlpkg: publish timed out — the upload stalled after connecting` )
                                        ( nurl_eprintln `hint: if 'nurlpkg search' works but publish stalls, suspect the network path, not the registry — a broken path MTU drops full-size packets, and only the upload is big enough to send them. Test with:` )
                                        ( nurl_eprintln `        ping -M do -s 1472 <registry-host>` )
                                        ( nurl_eprintln `      and try a smaller MSS (sysctl net.ipv4.tcp_mtu_probing=1, or clamp MSS on the router) before assuming the registry is down` )
                                    }
                                    PubConnect → {
                                        ( nurl_eprintln `nurlpkg: cannot connect to the registry` )
                                        ( nurl_eprintln `hint: check the registry URL ($NURL_REGISTRY or [package].registry) and any proxy/firewall` )
                                    }
                                    PubDns → {
                                        ( nurl_eprintln `nurlpkg: the registry host does not resolve` )
                                        ( nurl_eprintln `hint: check the registry URL ($NURL_REGISTRY or [package].registry) and your DNS` )
                                    }
                                    PubTls → {
                                        ( nurl_eprintln `nurlpkg: TLS handshake with the registry failed` )
                                        ( nurl_eprintln `hint: check the system CA bundle and the clock; a TLS-intercepting proxy will also do this` )
                                    }
                                    _ → {
                                        ( nurl_eprint `nurlpkg: publish failed (` )
                                        ( nurl_eprint ( publish_err_name ue ) )
                                        ( nurl_eprintln `)` )
                                    }
                                }
                                = rc 1
                            }
                        }
                        ( vec_free [u] digest )
                        ( string_free hex )
                        ( vec_free [u] tarball )
                    }
                }
            }
            ( string_free reg )
            ( string_free token )
            ( manifest_free m )
        }
    }
    ^ rc
}

// ── install <name>: fetch + build + install a binary tool ────────────
//
// `nurlpkg install` (no arg) resolves the current project's dependencies.
// `nurlpkg install <name>` is the `cargo install`-shaped sibling: fetch a
// published package from the registry, resolve ITS dependencies, compile
// its `src/main.nu` entry point with the installed compiler, and drop the
// resulting binary on $PATH (under $NURL_HOME/bin, default ~/.nurl/bin).
// If the package has no `src/main.nu` it is a LIBRARY: it lands under
// ./deps/<name> instead (with its transitive registry deps), so a plain
// folder of .nu files can pull a library without writing a nurl.toml.
//
// This is the payoff of the installable toolchain: an outside user runs
// `nurlpkg install nq` and gets a working program built from
// registry sources against the shipped stdlib (resolved via $NURL_STDLIB),
// no monorepo checkout required.

// $<name> if set and non-empty, else `fallback`. Returns an OWNED String.
@ __env_or s name s fallback → String {
    : ?String ev ( env_get name )
    ?? ev {
        T e → { ? > ( string_len e ) 0 { ^ e } { ( string_free e ) } }
        F → {}
    }
    ^ ( string_from fallback )
}

// Windows host? Windows always exports OS=Windows_NT; nothing else does.
// Used to pick the binary's extension, the temp root, and how to spawn a
// build driver (a `.bat` cannot be run by CreateProcess directly).
@ __is_windows → b {
    : ?String ev ( env_get `OS` )
    : ~ b w F
    ?? ev {
        T e → { = w ( nurl_str_eq ( string_data e ) `Windows_NT` ) ( string_free e ) }
        F → {}
    }
    ^ w
}

// Per-platform temp root for the staging dir: %TEMP%/%TMP% on Windows,
// $TMPDIR else /tmp on POSIX. Returns an OWNED String, no trailing sep.
@ __tmp_root → String {
    ? ( __is_windows ) {
        : ?String t ( env_get `TEMP` )
        ?? t { T e → { ? > ( string_len e ) 0 { ^ e } { ( string_free e ) } } F → {} }
        : ?String t2 ( env_get `TMP` )
        ?? t2 { T e → { ? > ( string_len e ) 0 { ^ e } { ( string_free e ) } } F → {} }
        ^ ( string_from `.` )
    } {}
    : ?String td ( env_get `TMPDIR` )
    ?? td { T e → { ? > ( string_len e ) 0 { ^ e } { ( string_free e ) } } F → {} }
    ^ ( string_from `/tmp` )
}

// Directory binaries are installed into: $NURL_HOME/bin, else the user
// home (HOME on POSIX, USERPROFILE on Windows) + /.nurl/bin. Forward
// slashes work on both platforms (Windows fopen/CreateProcess accept them).
@ __tool_bindir → String {
    : ?String nh ( env_get `NURL_HOME` )
    ?? nh {
        T h → {
            ? > ( string_len h ) 0 {
                : String d ( string_concat h ( string_from `/bin` ) )
                ( string_free h )
                ^ d
            } { ( string_free h ) }
        }
        F → {}
    }
    : String home ? ( __is_windows ) ( __env_or `USERPROFILE` `.` ) ( __env_or `HOME` `.` )
    : String out ( string_concat home ( string_from `/.nurl/bin` ) )
    ( string_free home )
    ^ out
}

// Spawn `prog args...` WITHOUT a shell (no POSIX-/cmd-specific syntax). On
// Windows a build driver is a `.bat`, which CreateProcess can't launch
// directly, so route through `cmd /c`. Returns 1 on success (exit 0).
// Inherits the current working directory, so callers `env_chdir` first.
@ __spawn s prog ( Vec s ) args s label → i {
    : ~ s rprog prog
    : ( Vec s ) rargs ( vec_new [s] )
    ? ( __is_windows ) {
        = rprog `cmd`
        ( vec_push [s] rargs `/c` )
        ( vec_push [s] rargs prog )
    } {}
    : i n ( vec_len [s] args )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [s] args i ) { T a → ( vec_push [s] rargs a ) F _ → {} }
        = i + i 1
    }
    : ~ i ok 0
    ?? ( process_run rprog rargs `` ) {
        T out → {
            ? ( output_success out ) { = ok 1 } {
                ( nurl_eprint `nurlpkg: ` ) ( nurl_eprint label ) ( nurl_eprintln ` failed:` )
                ( nurl_eprint ( output_stderr out ) )
            }
            ( output_free out )
        }
        F _ → { ( nurl_eprint `nurlpkg: ` ) ( nurl_eprint label ) ( nurl_eprintln ` could not launch` ) }
    }
    ( vec_free [s] rargs )
    ^ ok
}

// Print the freshly-installed package's [hints].postinstall message, if it
// declares one. Best-effort: any manifest read/parse trouble is silent —
// a missing hint must never make a successful install look like a failure.
@ __print_postinstall s pkgdir → v {
    : String mfp ( string_from pkgdir )
    ( string_push_str mfp `/nurl.toml` )
    : !Manifest ManifestErr mr ( manifest_load ( string_data mfp ) )
    ( string_free mfp )
    ?? mr {
        T m → {
            ? > ( string_len . m postinstall ) 0 {
                ( nurl_print `\n` )
                ( nurl_print ( string_data . m postinstall ) )
                ( nurl_print `\n` )
            } {}
            ( manifest_free m )
        }
        F _ → {}
    }
}

// pkgdir (absolute) holds the unpacked package (nurl.toml + src/main.nu).
// Resolve its deps in-process, build the entry point, and install the
// binary into bindir/name. Cross-platform: uses fs primitives + a
// shell-free driver spawn, no POSIX coreutils.
// Recursively copy a file or directory tree from `src` to `dst`, creating
// parent directories as needed. Returns 0 on success, 1 on any failure (or
// if `src` does not exist). Used to stage a tool's declared assets into
// $NURL_HOME/share/<name>/.
@ __copy_tree s src s dst → i {
    : i t ( nurl_path_type src )
    ? == t 1 {
        : String parent ( path_dirname dst )
        ?? ( dir_create_all ( string_data parent ) ) { T _ → {} F _ → {} }
        ( string_free parent )
        ?? ( fs_copy_file src dst ) { T _ → { ^ 0 } F _ → { ^ 1 } }
    } {}
    ? == t 2 {
        : ~ i rc 0
        ?? ( dir_create_all dst ) { T _ → {} F _ → { = rc 1 } }
        ? != rc 0 { ^ rc } {}
        : !( Vec String ) IoErr lr ( dir_list src )
        ?? lr {
            F _ → { = rc 1 }
            T entries → {
                : i n ( vec_len [String] entries )
                : ~ i k 0
                ~ < k n {
                    : ?String eo ( vec_get [String] entries k )
                    ?? eo {
                        T nm → {
                            : String s2 ( path_join src ( string_data nm ) )
                            : String d2 ( path_join dst ( string_data nm ) )
                            ? != 0 ( __copy_tree ( string_data s2 ) ( string_data d2 ) ) { = rc 1 } {}
                            ( string_free s2 )
                            ( string_free d2 )
                            ( string_free nm )
                        }
                        F _ → {}
                    }
                    = k + k 1
                }
                ( vec_free [String] entries )
            }
        }
        ^ rc
    } {}
    // Missing source or unsupported node type.
    ^ 1
}

// Stage a tool's declared `[install].assets` into $NURL_HOME/share/<name>/,
// preserving each path (so `static` lands at `<prefix>/share/<name>/static`,
// which a relocatable tool finds via `<exe-dir>/../share/<name>/…`). The
// share dir is a sibling of `bindir`. Cleared first so an upgrade never
// leaves a stale file behind. Returns 0 on success (including nothing to
// do), 1 if any asset path is missing or fails to copy.
// An asset path is safe to stage only if it stays inside the package: no
// absolute paths (a leading `/`) and no `..` anywhere (which `path_join`
// would happily let escape the share dir). Registry manifests are untrusted
// input, so reject rather than trust.
@ __asset_path_safe s a → b {
    : i n ( nurl_str_len a )
    ? == n 0 { ^ F } {}
    ? == ( nurl_str_get a 0 ) 47 { ^ F } {}
    : ~ i k 0
    ~ < k - n 1 {
        ? & == ( nurl_str_get a k ) 46 == ( nurl_str_get a + k 1 ) 46 { ^ F } {}
        = k + k 1
    }
    ^ T
}

@ __install_assets Manifest m s pkgdir s name s bindir → i {
    : i na ( vec_len [String] . m assets )
    ? == na 0 { ^ 0 } {}
    : String prefix ( path_dirname bindir )
    : String sharedir ( path_join ( string_data prefix ) `share` )
    ( string_free prefix )
    : String pkgshare ( path_join ( string_data sharedir ) name )
    ( string_free sharedir )
    ?? ( dir_remove_all ( string_data pkgshare ) ) { T _ → {} F _ → {} }
    : ~ i rc 0
    : ~ i k 0
    ~ < k na {
        : ?String ao ( vec_get [String] . m assets k )
        ?? ao {
            T a → {
                ? ! ( __asset_path_safe ( string_data a ) ) {
                    ( nurl_eprint `nurlpkg: unsafe asset path rejected: ` )
                    ( nurl_eprintln ( string_data a ) )
                    = rc 1
                } {
                    : String srcp ( path_join pkgdir ( string_data a ) )
                    : String dstp ( path_join ( string_data pkgshare ) ( string_data a ) )
                    ? != 0 ( __copy_tree ( string_data srcp ) ( string_data dstp ) ) {
                        ( nurl_eprint `nurlpkg: asset not staged: ` )
                        ( nurl_eprintln ( string_data a ) )
                        = rc 1
                    } {}
                    ( string_free srcp )
                    ( string_free dstp )
                }
            }
            F _ → {}
        }
        = k + k 1
    }
    ? == rc 0 {
        ( nurl_print `Assets → ` ) ( nurl_print ( string_data pkgshare ) ) ( nurl_print `\n` )
    } {}
    ( string_free pkgshare )
    ^ rc
}

@ __tool_build_and_install s name s pkgdir s binsrc → i {
    : String nurl ( __env_or `NURL` `nurl` )
    : String bindir ( __tool_bindir )
    : b win ( __is_windows )

    // Remember where we started so we can return after building in pkgdir.
    : ~ String orig ( string_new )
    ?? ( env_cwd ) { T c → { ( string_free orig ) = orig c } F _ → {} }

    : ~ i rc 1
    ?? ( env_chdir pkgdir ) {
        F _ → { ( nurl_eprintln `nurlpkg: cannot enter package directory` ) }
        T _ → {
            // 1. Resolve the tool's own deps into pkgdir/deps, IN-PROCESS
            //    (no recursive nurlpkg spawn). A depless tool resolves 0.
            : i drc ( __cmd_install )
            ? != drc 0 { = rc 1 } {
                // 2. Compile src/main.nu → .nurl-bin via the build driver.
                : ( Vec s ) cargs ( vec_new [s] )
                ( vec_push [s] cargs `src/main.nu` )
                ( vec_push [s] cargs `.nurl-bin` )
                : i ok2 ( __spawn ( string_data nurl ) cargs `compile` )
                ( vec_free [s] cargs )
                ? == ok2 0 { = rc 1 } { = rc 0 }
            }
        }
    }

    // Back to the original directory before touching bindir (which may be
    // relative, e.g. the "." fallback).
    ? > ( string_len orig ) 0 {
        ?? ( env_chdir ( string_data orig ) ) { T _ → {} F _ → {} }
    } {}

    ? == rc 0 {
        // 3. Install the freshly built binary onto $PATH. On Windows an
        //    executable needs the .exe extension to be runnable by name.
        // The build driver names the output `.nurl-bin`, but on Windows
        // nurl.bat appends `.exe` (EXEFILE=%OUTBASE%.exe) — so the file to
        // copy is `.nurl-bin.exe` there. Mismatch here silently became
        // "failed to install binary" on Windows.
        : String outbin ( string_with_cap 96 )
        ( string_push_str outbin pkgdir )
        ( string_push_str outbin `/.nurl-bin` )
        ? win { ( string_push_str outbin `.exe` ) } {}
        : String dest ( string_with_cap 96 )
        ( string_push_str dest ( string_data bindir ) )
        ( string_push_char dest 47 )
        ( string_push_str dest name )
        ? win { ( string_push_str dest `.exe` ) } {}

        ?? ( dir_create_all ( string_data bindir ) ) { T _ → {} F _ → {} }
        // Unlink the destination first. Writing INTO a binary that some
        // process is executing fails with ETXTBSY on Linux; unlinking the
        // directory entry and creating a fresh file succeeds, and the
        // running process keeps its old inode until it exits — which is
        // how every package manager replaces a running executable. This
        // surfaced as a bare "failed to install binary" while an old
        // `lingbot-map view` was still serving.
        : i32 _unl ( unlink ( string_data dest ) )
        ?? ( fs_copy_file ( string_data outbin ) ( string_data dest ) ) {
            F _ → { ( nurl_eprintln `nurlpkg: failed to install binary` ) = rc 1 }
            T _ → {
                // Restore the exec bit (fs_copy_file makes a 0644 content
                // copy); a no-op concept on Windows, so POSIX-only.
                ? ! win {
                    : ( Vec s ) chargs ( vec_new [s] )
                    ( vec_push [s] chargs `+x` )
                    ( vec_push [s] chargs ( string_data dest ) )
                    ?? ( process_run `chmod` chargs `` ) { T o → ( output_free o ) F _ → {} }
                    ( vec_free [s] chargs )
                } {}
                // Stage the package's declared runtime assets ([install].assets)
                // into <prefix>/share/<name>/ so the tool finds them relative to
                // its own executable (a registry install ships data, not just a
                // binary). A missing/failed asset fails the install.
                // The version is read here too, for the closing line.
                : String ver ( string_new )
                : String ampath ( path_join pkgdir `nurl.toml` )
                ?? ( manifest_load ( string_data ampath ) ) {
                    T am → {
                        ? != 0 ( __install_assets am pkgdir name ( string_data bindir ) ) { = rc 1 } {}
                        ( string_push_str ver ( string_data . am version ) )
                        ( manifest_free am )
                    }
                    F _ → {}
                }
                ( string_free ampath )
                // Show the package's [hints].postinstall message, if any.
                ( __print_postinstall pkgdir )
                // The LAST line says what landed and where — the name and
                // version, not a bare "done".
                ( nurl_print name )
                ? > ( string_len ver ) 0 {
                    ( nurl_print ` ` ) ( nurl_print ( string_data ver ) )
                } {}
                ( nurl_print ` installed → ` )
                ( nurl_print ( string_data dest ) ) ( nurl_print `\n` )
                ( string_free ver )
            }
        }
        ( string_free outbin )
        ( string_free dest )
    } {}

    ( string_free orig )
    ( string_free nurl )
    ( string_free bindir )
    ^ rc
}

// True if ./nurl.toml exists and already declares `name` under
// [dependencies] (so a library install doesn't duplicate the entry).
@ __toml_declares_dep s name → b {
    : ~ b found F
    ?? ( manifest_load `nurl.toml` ) {
        T m → {
            : i n ( vec_len [Dep] . m dependencies )
            : ~ i k 0
            ~ < k n {
                : ?Dep d ( vec_get [Dep] . m dependencies k )
                ?? d {
                    T dv → { ? != 0 ( nurl_str_eq ( string_data . dv name ) name ) { = found T } {} }
                    F _ → {}
                }
                = k + k 1
            }
            ( manifest_free m )
        }
        F _ → {}
    }
    ^ found
}

// `install <name>` on a LIBRARY package: land the latest version (and its
// transitive registry deps) under ./deps/<name> — the same layout a
// manifest-driven `nurlpkg install` produces — so a plain folder of .nu
// files can pull a registry library without writing a nurl.toml first.
// When a nurl.toml IS present, the dependency is recorded there too (same
// effect as `nurlpkg add <name> --version ^<ver>`), so a later
// manifest-driven install reproduces this state.
@ __install_lib_deps s name s reg → i {
    ( nurl_print `'` ) ( nurl_print name )
    ( nurl_print `' is a library — installing into ./deps/\n` )
    : ( Vec Dep ) roots ( vec_new [Dep] )
    ( vec_push [Dep] roots @ Dep {
        ( string_from name ) ( string_new ) ( string_from `*` ) ( string_new )
    } )
    : ( @ String s ) fetch \ s nm → String { ^ ( pkg_fetch_index reg nm ) }
    : ~ i rc 0
    : ~ String rootver ( string_new )
    : !( Vec LockPkg ) ResolveErr rr ( resolve_registry roots reg fetch )
    ?? rr {
        F e → {
            ( nurl_eprint `nurlpkg: registry resolution failed (` )
            ( nurl_eprint ( resolve_err_name e ) ) ( nurl_eprintln `)` )
            = rc 1
        }
        T locked → {
            : i ln ( vec_len [LockPkg] locked )
            : ~ i k 0
            ~ < k ln {
                : ?LockPkg po ( vec_get [LockPkg] locked k )
                ?? po {
                    T p → {
                        : !i PkgFetchErr ir ( pkg_install_one reg ( string_data . p name ) ( string_data . p version ) ( string_data . p checksum ) `deps` )
                        ?? ir {
                            T _ → {
                                ( nurl_print `  ` ) ( nurl_print ( string_data . p name ) )
                                ( nurl_print ` ` ) ( nurl_print ( string_data . p version ) )
                                ( nurl_print ` → deps/` ) ( nurl_print ( string_data . p name ) )
                                ( nurl_print `\n` )
                                ? != 0 ( nurl_str_eq ( string_data . p name ) name ) {
                                    ( string_free rootver )
                                    = rootver ( string_from ( string_data . p version ) )
                                } {}
                            }
                            F fe → {
                                ( nurl_eprint `  ` ) ( nurl_eprint ( string_data . p name ) )
                                ( nurl_eprint `: ` ) ( nurl_eprintln ( pkg_err_name fe ) )
                                = rc 1
                            }
                        }
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ( lockpkgs_free locked )
        }
    }
    ( __deps_free_vec roots )
    ? & == rc 0 & ( file_exists `nurl.toml` ) > ( string_len rootver ) 0 {
        ? ( __toml_declares_dep name ) {} {
            : String req ( string_with_cap 24 )
            ( string_push_char req 94 )
            ( string_push_str req ( string_data rootver ) )
            : i arc ( __cmd_add name `` ( string_data req ) )
            ? != arc 0 { = rc arc } {}
            ( string_free req )
        }
    } {}
    ? == rc 0 {
        ( nurl_print `done. Import it with:  $ deps/` )
        ( nurl_print name )
        ( nurl_print `/src/<module>.nu  (backtick-quoted)\n` )
    } {}
    ( string_free rootver )
    ^ rc
}

@ __cmd_install_tool s name → i {
    : String regS ( __reg_default )
    : s reg ( string_data regS )
    : String idx ( pkg_fetch_index reg name )
    ? == 0 ( string_len idx ) {
        ( nurl_eprint `nurlpkg: package '` ) ( nurl_eprint name )
        ( nurl_eprintln `' not found in the registry` )
        ( string_free idx ) ( string_free regS )
        ^ 1
    } {}
    : !RegIndex RegIndexErr pr ( regindex_parse ( string_data idx ) )
    ( string_free idx )
    : ~ i rc 1
    ?? pr {
        F e → {
            ( nurl_eprint `nurlpkg: malformed registry index (` )
            ( nurl_eprint ( regindex_err_name e ) ) ( nurl_eprintln `)` )
        }
        T ridx → {
            : i sel ( regindex_select ridx `*` )
            ? < sel 0 { ( nurl_eprintln `nurlpkg: no installable version found` ) } {
                ?? ( vec_get [IdxVersion] . ridx versions sel ) {
                    F _ → {}
                    T iv → {
                        // Staging dir under the platform temp root (absolute,
                        // so we can chdir back out after building).
                        : String troot ( __tmp_root )
                        : String stage ( string_with_cap 96 )
                        ( string_push_str stage ( string_data troot ) )
                        ( string_push_str stage `/nurlpkg-tool-` )
                        ( string_push_str stage name )
                        ( string_free troot )
                        // Clean + recreate it with cross-platform fs ops
                        // (no rm -rf / mkdir -p shell-out).
                        ?? ( dir_remove_all ( string_data stage ) ) { T _ → {} F _ → {} }
                        ?? ( dir_create_all ( string_data stage ) ) { T _ → {} F _ → {} }
                        : !i PkgFetchErr fr ( pkg_install_one reg name ( string_data . iv version ) ( string_data . iv checksum ) ( string_data stage ) )
                        ?? fr {
                            F fe → {
                                ( nurl_eprint `nurlpkg: download failed (` )
                                ( nurl_eprint ( pkg_err_name fe ) ) ( nurl_eprintln `)` )
                            }
                            T _ → {
                                : String pkgdir ( string_with_cap 96 )
                                ( string_push_str pkgdir ( string_data stage ) )
                                ( string_push_char pkgdir 47 ) ( string_push_str pkgdir name )
                                : String binsrc ( string_concat ( string_from ( string_data pkgdir ) ) ( string_from `/src/main.nu` ) )
                                ? ! ( file_exists ( string_data binsrc ) ) {
                                    // No src/main.nu → a library. Install it
                                    // under ./deps/ instead of erroring.
                                    = rc ( __install_lib_deps name reg )
                                } {
                                    = rc ( __tool_build_and_install name ( string_data pkgdir ) ( string_data binsrc ) )
                                }
                                ( string_free binsrc ) ( string_free pkgdir )
                            }
                        }
                        ( string_free stage )
                    }
                }
            }
            ( regindex_free ridx )
        }
    }
    ( string_free regS )
    ^ rc
}

@ __cmd_install → i {
    ? ! ( file_exists `nurl.toml` ) {
        ( nurl_eprintln `nurlpkg: no nurl.toml in the current directory (run 'nurlpkg init <name>' first)` )
        ^ 1
    } {}
    : !String IoErr cwdR ( env_cwd )
    : ~ String cwd ( string_new )
    ?? cwdR {
        T c → = cwd c
        F _ → {
            ( nurl_eprintln `nurlpkg: failed to determine current directory` )
            ^ 1
        }
    }
    : s cwd_s ( string_data cwd )
    // Ensure deps/ exists. Skip the mkdir entirely if it already
    // exists to dodge the AlreadyExists/IoErr nested-match path
    // (nested enum match-on-enum-value codegen has a known issue —
    // see compiler/tests/should_warn_*; refactor when fixed).
    ? ! ( file_exists `deps` ) {
        : !v IoErr dr ( dir_create `deps` )
        ?? dr {
            T _ → {}
            F _ → {
                ( nurl_eprintln `nurlpkg: failed to create deps/ directory` )
                ( string_free cwd )
                ^ 1
            }
        }
    } {}
    : !Manifest ManifestErr mr ( manifest_load `nurl.toml` )
    : ~ i rc 0
    ?? mr {
        F e → {
            ( nurl_eprint `nurlpkg: failed to parse nurl.toml (` )
            ( nurl_eprint ( manifest_err_name e ) )
            ( nurl_eprintln `)` )
            = rc 1
        }
        T root → {
            : i n ( vec_len [Dep] . root dependencies )
            ( nurl_print `installing ` )
            ( nurl_print ( nurl_str_int n ) )
            ( nurl_print ` direct dependencies into deps/\n` )
            // BFS queues. `dq` holds Dep records yet to be processed;
            // `seen` holds absolute target paths already installed.
            : ( Vec Dep ) dq ( vec_new [Dep] )
            : ( Vec String ) seen ( vec_new [String] )
            : ~ i k 0
            ~ < k n {
                : ?Dep dk ( vec_get [Dep] . root dependencies k )
                ?? dk {
                    T d → ( vec_push [Dep] dq @ Dep {
                        ( string_from ( string_data . d name ) )
                        ( string_from ( string_data . d path ) )
                        ( string_from ( string_data . d version ) )
                        ( string_from ( string_data . d registry ) )
                    } )
                    F _ → {}
                }
                = k + k 1
            }
            // Drain the queue. After each successful install, enqueue
            // the sub-manifest's own deps with paths re-anchored.
            : ~ i tx 0
            : ~ ( Vec String ) next_queue ( vec_new [String] )
            ~ > ( vec_len [Dep] dq ) tx {
                : ?Dep dk ( vec_get [Dep] dq tx )
                ?? dk {
                    T d → {
                        : i one_rc ( __install_one cwd_s d seen next_queue )
                        ? != one_rc 0 { = rc 1 } {}
                        ( dep_free d )
                    }
                    F _ → {}
                }
                = tx + tx 1
            }
            ( vec_free [Dep] dq )
            // Process the transitive frontier: for each newly-installed
            // target, load its manifest and enqueue children. Loop until
            // no new entries are added.
            ~ > ( vec_len [String] next_queue ) 0 {
                : ( Vec Dep ) next_dq ( vec_new [Dep] )
                : i nq ( vec_len [String] next_queue )
                : ~ i j 0
                ~ < j nq {
                    : ?String pkj ( vec_get [String] next_queue j )
                    ?? pkj {
                        T pk → {
                            : i en_rc ( __enqueue_transitive ( string_data pk ) cwd_s next_dq )
                            ? != en_rc 0 { = rc 1 } {}
                        }
                        F _ → {}
                    }
                    = j + j 1
                }
                // Free the frontier we just consumed.
                : ~ i fk 0
                ~ < fk nq {
                    : ?String pkj ( vec_get [String] next_queue fk )
                    ?? pkj { T pk → ( string_free pk ) F _ → {} }
                    = fk + fk 1
                }
                ( vec_free [String] next_queue )
                = next_queue ( vec_new [String] )
                : i ndq ( vec_len [Dep] next_dq )
                : ~ i di 0
                ~ < di ndq {
                    : ?Dep dk2 ( vec_get [Dep] next_dq di )
                    ?? dk2 {
                        T d → {
                            : i one_rc ( __install_one cwd_s d seen next_queue )
                            ? != one_rc 0 { = rc 1 } {}
                            ( dep_free d )
                        }
                        F _ → {}
                    }
                    = di + di 1
                }
                ( vec_free [Dep] next_dq )
            }
            ( vec_free [String] next_queue )
            : i sn ( vec_len [String] seen )
            : ~ i si 0
            ~ < si sn {
                : ?String pk ( vec_get [String] seen si )
                ?? pk { T s → ( string_free s ) F _ → {} }
                = si + si 1
            }
            ( vec_free [String] seen )
            // Registry pass: resolve + download + verify + unpack the
            // registry deps (path deps were handled by the BFS above).
            : ( Vec LockPkg ) regpkgs ( vec_new [LockPkg] )
            : i reg_rc ( __install_registry root cwd_s regpkgs )
            ? != reg_rc 0 { = rc 1 } {}
            // The closing line names the package whose deps these are —
            // captured before the manifest is freed.
            : String who ( string_from ( string_data . root name ) )
            ? > ( string_len . root version ) 0 {
                ( string_push_char who 32 )
                ( string_push_str who ( string_data . root version ) )
            } {}
            ( manifest_free root )
            // Regenerate the lockfile from the resulting deps/ tree. We do
            // this even if some deps failed — a partial lockfile correctly
            // reflects what's actually installed. Registry entries carry
            // their resolved source + tarball checksum.
            : i lr ( __write_lockfile regpkgs )
            ? != lr 0 { = rc 1 } {}
            ( lockpkgs_free regpkgs )
            ( nurl_print ( string_data who ) )
            ( nurl_print `: dependencies installed\n` )
            ( string_free who )
        }
    }
    ( string_free cwd )
    ^ rc
}

// ── deps ────────────────────────────────────────────────────────

@ __cmd_deps → i {
    ? ! ( file_exists `nurl.toml` ) {
        ( nurl_eprintln `nurlpkg: no nurl.toml in the current directory (run 'nurlpkg init <name>' first)` )
        ^ 1
    } {}
    : !Manifest ManifestErr mr ( manifest_load `nurl.toml` )
    : ~ i rc 0
    ?? mr {
        F e → {
            ( nurl_eprint `nurlpkg: failed to parse nurl.toml (` )
            ( nurl_eprint ( manifest_err_name e ) )
            ( nurl_eprintln `)` )
            = rc 1
        }
        T m → {
            : i n ( vec_len [Dep] . m dependencies )
            : ~ i k 0
            ~ < k n {
                : ?Dep dk ( vec_get [Dep] . m dependencies k )
                ?? dk {
                    T d → {
                        ( nurl_print ( string_data . d name ) )
                        ( nurl_print `\tpath=` )
                        ? > ( string_len . d path ) 0 {
                            ( nurl_print ( string_data . d path ) )
                        } { ( nurl_print `-` ) }
                        ( nurl_print `\tversion=` )
                        ? > ( string_len . d version ) 0 {
                            ( nurl_print ( string_data . d version ) )
                        } { ( nurl_print `-` ) }
                        ( nurl_print `\n` )
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ( manifest_free m )
        }
    }
    ^ rc
}

// ── test runner (C3) ──────────────────────────────────────────────
//
// `nurlpkg test` ships the compiler-suite pattern as a user-facing tool:
// every `tests/*.nu` is compiled and run; exit 0 = pass. If
// `tests/outputs/<name>.txt` exists, its bytes must match the program's
// stdout exactly (a golden); otherwise the exit code alone decides.
//
// The build driver is resolved like every other nurlpkg build path
// (`build`, `install`, the publish gate): $NURL_CC first (a command taking
// `<flags> <src> <outbin>`), then a toolchain checkout's own `./nurl.sh` /
// `nurl.bat` when the command runs from one, then $NURL, then the installed
// `nurl` on PATH. Defaulting to a bare `./nurl.sh` made `test` and `bench`
// the only commands that worked in the toolchain repo and nowhere else — an
// installed-toolchain package got "./nurl.sh: not found" for every test.
// Test binaries land in /tmp.

@ __test_basename s path → String {
    : i n ( nurl_str_len path )
    : ~ i start 0
    : ~ i k 0
    ~ < k n { ? == ( nurl_str_get path k ) 47 { = start + k 1 } {} = k + k 1 }  // '/'
    : ~ i end n
    ? & >= - n start 3 & == ( nurl_str_get path - n 3 ) 46 & == ( nurl_str_get path - n 2 ) 110 == ( nurl_str_get path - n 1 ) 117 { = end - n 3 } {}  // ".nu"
    : String out ( string_with_cap + - end start 1 )
    = k start
    ~ < k end { ( string_push_char out ( nurl_str_get path k ) ) = k + k 1 }
    ^ out
}

@ __test_driver → String {
    ?? ( env_get `NURL_CC` ) {
        T v → { ? > ( string_len v ) 0 { ^ v } { ( string_free v ) } }
        F _ → {}
    }
    // A toolchain checkout builds with its OWN freshly built compiler, not
    // whatever `nurl` happens to be installed — keep that when the wrapper
    // is right here in the working directory.
    : s local ? ( __is_windows ) `nurl.bat` `./nurl.sh`
    ? ( file_exists local ) { ^ ( string_from local ) } {}
    ^ ( __env_or `NURL` `nurl` )
}

@ __test_report String name s status s detail → v {
    ( nurl_print `  ` ) ( nurl_print status ) ( nurl_print ` ` ) ( nurl_print ( string_data name ) )
    ? > ( nurl_str_len detail ) 0 { ( nurl_print ` ` ) ( nurl_print detail ) } {}
    ( nurl_print `\n` )
}

// True iff the golden file's bytes equal stdout[0..outlen).
@ __golden_match s goldp s out i outlen → b {
    : ~ b ok F
    ?? ( read_file goldp ) {
        T g → {
            ? == ( string_len g ) outlen { = ok == ( memcmp ( string_data g ) out outlen ) 0 } {}
            ( string_free g )
        }
        F _ → {}
    }
    ^ ok
}

// Compile + run one test. Returns 0 on pass.
@ __run_one s src s driver → i {
    : String name ( __test_basename src )
    : String bin ( string_with_cap 64 )
    ( string_push_str bin `/tmp/nurlpkg_test_` )
    ( string_push_str bin ( string_data name ) )

    : String ccmd ( string_with_cap 128 )
    ( string_push_str ccmd driver )
    ( string_push_str ccmd ` -O0 ` )
    ( string_push_str ccmd src )
    ( string_push_char ccmd 32 )
    ( string_push_str ccmd ( string_data bin ) )

    : ~ i result 1
    : ~ b compiled F
    ?? ( process_run_shell ( string_data ccmd ) ) {
        T out → {
            ? ( output_success out ) { = compiled T } {
                ( __test_report name `FAIL` `(compile error)` )
                ( nurl_eprint ( output_stderr out ) )
            }
            ( output_free out )
        }
        F _ → { ( __test_report name `FAIL` `(could not launch compiler)` ) }
    }
    ( string_free ccmd )

    ? compiled {
        ?? ( process_run_shell ( string_data bin ) ) {
            T out → {
                : i ec ( output_exit_code out )
                : String goldp ( string_with_cap 64 )
                ( string_push_str goldp `tests/outputs/` )
                ( string_push_str goldp ( string_data name ) )
                ( string_push_str goldp `.txt` )
                ? ( file_exists ( string_data goldp ) ) {
                    ? ( __golden_match ( string_data goldp ) ( output_stdout out ) ( output_stdout_len out ) ) {
                        ( __test_report name `PASS` `` ) = result 0
                    } {
                        ( __test_report name `FAIL` `(output mismatch)` )
                    }
                } {
                    ? == ec 0 { ( __test_report name `PASS` `` ) = result 0 } { ( __test_report name `FAIL` `(nonzero exit)` ) }
                }
                ( string_free goldp )
                ( output_free out )
            }
            F _ → { ( __test_report name `FAIL` `(could not run)` ) }
        }
    } {}

    ( string_free bin )
    ( string_free name )
    ^ result
}

// Owns `files` (the fs_glob result): runs each, frees them, reports.
@ __run_tests ( Vec String ) files → i {
    : ( @ i String String ) cs \ String a String b → i { ^ ( cmp_string a b ) }
    ( sort_by [String] files cs )
    : String driver ( __test_driver )
    : ~ i pass 0
    : ~ i fail 0
    : ~ i k 0
    ~ < k ( vec_len [String] files ) {
        ?? ( vec_get [String] files k ) {
            T src → {
                ? == ( __run_one ( string_data src ) ( string_data driver ) ) 0 { = pass + pass 1 } { = fail + fail 1 }
                ( string_free src )
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free [String] files )
    ( string_free driver )
    ( nurl_print `\n` )
    ( nurl_print `PASS ` ) ( nurl_print ( nurl_str_int pass ) )
    ( nurl_print ` · FAIL ` ) ( nurl_print ( nurl_str_int fail ) ) ( nurl_print `\n` )
    ^ ? == fail 0 0 1
}

@ __cmd_test → i {
    // Resolve deps/ first, exactly like `build` and `install` do — a test that
    // imports `deps/<pkg>/src/...` cannot compile without it, and requiring a
    // separate `nurlpkg install` made `test` the odd one out.
    ? ( file_exists `nurl.toml` ) {
        ? != ( __cmd_install ) 0 { ^ 1 } {}
    } {}
    ^ ?? ( fs_glob `tests/*.nu` ) {
        F _ → { ( nurl_eprintln `nurlpkg: no tests/ directory (expected tests/*.nu)` ) 1 }
        T files → {
            ? == ( vec_len [String] files ) 0 {
                ( nurl_eprintln `nurlpkg: no tests found (expected tests/*.nu)` )
                ( vec_free [String] files )
                1
            } {
                ( __run_tests files )
            }
        }
    }
}

// ── bench runner (C4) ─────────────────────────────────────────────
//
// `nurlpkg bench` compiles + runs every `benches/*.nu` and streams its
// stdout (each bench program prints its own std/bench.nu report). No
// goldens — wall time is machine-dependent. A bench "fails" only if it
// won't compile or exits nonzero. Build driver as for `test` ($NURL_CC,
// else a checkout's ./nurl.sh, else the installed nurl).

@ __run_bench_one s src s driver → i {
    : String name ( __test_basename src )
    : String bin ( string_with_cap 64 )
    ( string_push_str bin `/tmp/nurlpkg_bench_` )
    ( string_push_str bin ( string_data name ) )

    : String ccmd ( string_with_cap 128 )
    ( string_push_str ccmd driver )
    ( string_push_str ccmd ` -O2 ` )
    ( string_push_str ccmd src )
    ( string_push_char ccmd 32 )
    ( string_push_str ccmd ( string_data bin ) )

    : ~ i result 1
    : ~ b compiled F
    ?? ( process_run_shell ( string_data ccmd ) ) {
        T out → {
            ? ( output_success out ) { = compiled T } {
                ( nurl_print `── ` ) ( nurl_print ( string_data name ) ) ( nurl_print ` (compile error)\n` )
                ( nurl_eprint ( output_stderr out ) )
            }
            ( output_free out )
        }
        F _ → { ( nurl_print `── ` ) ( nurl_print ( string_data name ) ) ( nurl_print ` (could not launch compiler)\n` ) }
    }
    ( string_free ccmd )

    ? compiled {
        ( nurl_print `── ` ) ( nurl_print ( string_data name ) ) ( nurl_print `\n` )
        ?? ( process_run_shell ( string_data bin ) ) {
            T out → {
                : i olen ( output_stdout_len out )
                ? > olen 0 { : i _w ( write 1 # *u ( output_stdout out ) olen ) } {}
                ? == ( output_exit_code out ) 0 { = result 0 } {}
                ( output_free out )
            }
            F _ → { ( nurl_print `(could not run)\n` ) }
        }
    } {}

    ( string_free bin )
    ( string_free name )
    ^ result
}

@ __run_benches ( Vec String ) files → i {
    : ( @ i String String ) cs \ String a String b → i { ^ ( cmp_string a b ) }
    ( sort_by [String] files cs )
    : String driver ( __test_driver )
    : ~ i ran 0
    : ~ i failed 0
    : ~ i k 0
    ~ < k ( vec_len [String] files ) {
        ?? ( vec_get [String] files k ) {
            T src → {
                ? == ( __run_bench_one ( string_data src ) ( string_data driver ) ) 0 { = ran + ran 1 } { = failed + failed 1 }
                ( string_free src )
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free [String] files )
    ( string_free driver )
    ( nurl_print `\nran ` ) ( nurl_print ( nurl_str_int ran ) )
    ( nurl_print ` · failed ` ) ( nurl_print ( nurl_str_int failed ) ) ( nurl_print `\n` )
    ^ ? == failed 0 0 1
}

@ __cmd_bench → i {
    ? ( file_exists `nurl.toml` ) {
        ? != ( __cmd_install ) 0 { ^ 1 } {}
    } {}
    ^ ?? ( fs_glob `benches/*.nu` ) {
        F _ → { ( nurl_eprintln `nurlpkg: no benches/ directory (expected benches/*.nu)` ) 1 }
        T files → {
            ? == ( vec_len [String] files ) 0 {
                ( nurl_eprintln `nurlpkg: no benchmarks found (expected benches/*.nu)` )
                ( vec_free [String] files )
                1
            } {
                ( __run_benches files )
            }
        }
    }
}

// ── self-update: upgrade the toolchain itself ───────────────────
//
// Deliberately NOT spelled `nurlpkg update`: that has moved this project's
// dependency requirements since 0.4, and silently changing what it means
// would be worse than any naming win. The canonical spelling is
// `nurl upgrade` (what the update notice prints); this is the same command
// under the name other package managers use for it, so either guess lands.

// The value that follows `--name` in argv[from..], or an empty String.
@ __flag_value s name i from → String {
    : i argc ( env_args_count )
    : ~ i k from
    : ~ String out ( string_new )
    ~ < k argc {
        : String a ( env_arg k )
        : i nx + k 1
        ? & != 0 ( nurl_str_eq ( string_data a ) name ) < nx argc {
            ( string_free out )
            = out ( env_arg nx )
        } {}
        ( string_free a )
        = k + k 1
    }
    ^ out
}

// T when `--name` appears anywhere in argv[from..].
@ __has_flag s name i from → b {
    : i argc ( env_args_count )
    : ~ i k from
    ~ < k argc {
        : String a ( env_arg k )
        : b hit != 0 ( nurl_str_eq ( string_data a ) name )
        ( string_free a )
        ? hit { ^ T } {}
        = k + k 1
    }
    ^ F
}

@ __cmd_self_update → i {
    ? != 0 ( __reject_unknown_flags `self-update` `--check --force --version` 2 ) { ^ 1 } {}
    : b check_only ( __has_flag `--check` 2 )
    : b force ( __has_flag `--force` 2 )
    : String want ( __flag_value `--version` 2 )
    : i rc ( toolchain_upgrade ( string_data want ) ( nurl_version ) check_only force )
    ( string_free want )
    ^ rc
}

// ── dispatch ─────────────────────────────────────────────────────

// Was this invocation the self-update itself? If so, skip the trailing
// "a newer toolchain is out" notice: the version baked into THIS process
// is the one we just replaced on disk, so the notice would fire against
// the toolchain the user has already upgraded away from.
@ __is_self_update → b {
    ? < ( env_args_count ) 2 { ^ F } {}
    : String a ( env_arg 1 )
    : s v ( string_data a )
    : b hit | | != 0 ( nurl_str_eq v `self-update` ) != 0 ( nurl_str_eq v `upgrade` ) != 0 ( nurl_str_eq v `self-upgrade` )
    ( string_free a )
    ^ hit
}

// Run the command, then print a best-effort "a newer toolchain is out" notice
// AFTER its output (stderr; cached, opt-out — see stdlib/ext/update_check.nu).
@ main → i {
    : i rc ( __nurlpkg_run )
    ? ( __is_self_update ) {} { ( update_check_notice ( nurl_version ) ) }
    ^ rc
}

@ __nurlpkg_run → i {
    : i argc ( env_args_count )
    ? < argc 2 {
        ( __print_usage )
        ^ 0
    } {}
    : String sub ( env_arg 1 )
    : s s_sub ( string_data sub )
    // help FIRST — before any command can act. `nurlpkg <cmd> --help`,
    // `nurlpkg help <cmd>`, `nurlpkg --help` / -h all end here.
    ? | != 0 ( nurl_str_eq s_sub `--help` ) != 0 ( nurl_str_eq s_sub `-h` ) {
        ( __print_usage )
        ( string_free sub )
        ^ 0
    } {}
    ? & != 0 ( nurl_str_eq s_sub `help` ) >= argc 3 {
        : String hc ( env_arg 2 )
        : b known ( __cmd_help ( string_data hc ) )
        ? known {} { ( __print_usage ) }
        ( string_free hc )
        ( string_free sub )
        ^ 0
    } {}
    ? ( __wants_help 2 ) {
        : b known2 ( __cmd_help s_sub )
        ? known2 {} { ( __print_usage ) }
        ( string_free sub )
        ^ 0
    } {}
    ? | | != 0 ( nurl_str_eq s_sub `--version` ) != 0 ( nurl_str_eq s_sub `-v` ) != 0 ( nurl_str_eq s_sub `version` ) {
        ( nurl_print ( nurl_version ) ) ( nurl_print `\n` )
        ( string_free sub )
        ^ 0
    } {}
    // Upgrade the toolchain. `nurl upgrade` routes here too.
    ? | | != 0 ( nurl_str_eq s_sub `self-update` ) != 0 ( nurl_str_eq s_sub `upgrade` ) != 0 ( nurl_str_eq s_sub `self-upgrade` ) {
        ( string_free sub )
        ^ ( __cmd_self_update )
    } {}
    ? != 0 ( nurl_str_eq s_sub `init` ) {
        : String name ? >= argc 3 ( env_arg 2 ) ( string_new )
        : i rc ( __cmd_init ( string_data name ) )
        ( string_free name )
        ( string_free sub )
        ^ rc
    } {}
    ? != 0 ( nurl_str_eq s_sub `info` ) {
        // `info` (no arg) → local manifest; `info <name>` → registry package.
        ? >= argc 3 {
            : String name ( env_arg 2 )
            : i rc ( __cmd_registry_info ( string_data name ) )
            ( string_free name )
            ( string_free sub )
            ^ rc
        } {}
        ( string_free sub )
        ^ ( __cmd_info )
    } {}
    ? != 0 ( nurl_str_eq s_sub `deps` ) {
        ( string_free sub )
        ? != 0 ( __reject_unknown_flags `deps` `` 2 ) { ^ 1 } {}
        ^ ( __cmd_deps )
    } {}
    ? != 0 ( nurl_str_eq s_sub `install` ) {
        ( string_free sub )
        // `install <name>` → install a binary tool; bare `install` → deps.
        ? >= argc 3 {
            : String tname ( env_arg 2 )
            : i rc ( __cmd_install_tool ( string_data tname ) )
            ( string_free tname )
            ^ rc
        } {}
        ^ ( __cmd_install )
    } {}
    ? != 0 ( nurl_str_eq s_sub `lock` ) {
        ( string_free sub )
        ? != 0 ( __reject_unknown_flags `lock` `` 2 ) { ^ 1 } {}
        ^ ( __cmd_lock )
    } {}
    ? != 0 ( nurl_str_eq s_sub `build` ) {
        ( string_free sub )
        ? != 0 ( __reject_unknown_flags `build` `--out` 2 ) { ^ 1 } {}
        : ~ String bname ( string_new )
        : ~ String bout ( string_new )
        : ~ i bk 2
        ~ < bk argc {
            : String ba ( env_arg bk )
            ? != 0 ( nurl_str_eq ( string_data ba ) `--out` ) {
                ? < + bk 1 argc {
                    : String bo ( env_arg + bk 1 )
                    ( string_free bout )
                    = bout bo
                    = bk + bk 1
                } {}
            } {
                ? == ( nurl_str_get ( string_data ba ) 0 ) 45 {} {
                    ( string_free bname )
                    = bname ( string_from ( string_data ba ) )
                }
            }
            ( string_free ba )
            = bk + bk 1
        }
        : i brc ( __cmd_build ( string_data bname ) ( string_data bout ) )
        ( string_free bname ) ( string_free bout )
        ^ brc
    } {}
    ? != 0 ( nurl_str_eq s_sub `publish` ) {
        ( string_free sub )
        ? != 0 ( __reject_unknown_flags `publish` `--dry-run --dryrun` 2 ) { ^ 1 } {}
        : ~ b dry F
        : ~ i pk 2
        ~ < pk argc {
            : String pa ( env_arg pk )
            ? | != 0 ( nurl_str_eq ( string_data pa ) `--dry-run` ) != 0 ( nurl_str_eq ( string_data pa ) `--dryrun` ) { = dry T } {}
            ( string_free pa )
            = pk + pk 1
        }
        ^ ( __cmd_publish dry )
    } {}
    ? != 0 ( nurl_str_eq s_sub `login` ) {
        ( string_free sub )
        ^ ( __cmd_login )
    } {}
    ? != 0 ( nurl_str_eq s_sub `logout` ) {
        // nurlpkg logout [--revoke]
        : ~ i revoke 0
        ? >= argc 3 {
            : String f ( env_arg 2 )
            ? != 0 ( nurl_str_eq ( string_data f ) `--revoke` ) { = revoke 1 } {}
            ( string_free f )
        } {}
        ( string_free sub )
        ^ ( __cmd_logout revoke )
    } {}
    ? != 0 ( nurl_str_eq s_sub `search` ) {
        : ~ String q ( string_new )
        ? >= argc 3 { = q ( env_arg 2 ) } {}
        : i rc ( __cmd_search ( string_data q ) )
        ( string_free q )
        ( string_free sub )
        ^ rc
    } {}
    ? | != 0 ( nurl_str_eq s_sub `yank` ) != 0 ( nurl_str_eq s_sub `unyank` ) {
        : i yk ( nurl_str_eq s_sub `yank` )
        ? < argc 4 {
            ( nurl_eprintln `nurlpkg: usage: nurlpkg yank|unyank <name> <version>` )
            ( string_free sub )
            ^ 1
        } {}
        : String name ( env_arg 2 )
        : String version ( env_arg 3 )
        : i rc ( __cmd_yank ( string_data name ) ( string_data version ) yk )
        ( string_free version )
        ( string_free name )
        ( string_free sub )
        ^ rc
    } {}
    ? != 0 ( nurl_str_eq s_sub `add` ) {
        // Parse: nurlpkg add <name> [--path P] [--version V]
        : ~ String name ( string_new )
        : ~ String path ( string_new )
        : ~ String version ( string_new )
        ? >= argc 3 { = name ( env_arg 2 ) } {}
        : ~ i ai 3
        ~ < ai argc {
            : String flag ( env_arg ai )
            : s flag_s ( string_data flag )
            ? != 0 ( nurl_str_eq flag_s `--path` ) {
                ? < + ai 1 argc {
                    ( string_free path )
                    = path ( env_arg + ai 1 )
                    = ai + ai 2
                } { = ai + ai 1 }
            } {
                ? != 0 ( nurl_str_eq flag_s `--version` ) {
                    ? < + ai 1 argc {
                        ( string_free version )
                        = version ( env_arg + ai 1 )
                        = ai + ai 2
                    } { = ai + ai 1 }
                } { = ai + ai 1 }
            }
            ( string_free flag )
        }
        : i rc ( __cmd_add ( string_data name ) ( string_data path ) ( string_data version ) )
        ( string_free version )
        ( string_free path )
        ( string_free name )
        ( string_free sub )
        ^ rc
    } {}
    ? != 0 ( nurl_str_eq s_sub `remove` ) {
        : ~ String name ( string_new )
        ? >= argc 3 { = name ( env_arg 2 ) } {}
        : i rc ( __cmd_remove ( string_data name ) )
        ( string_free name )
        ( string_free sub )
        ^ rc
    } {}
    ? != 0 ( nurl_str_eq s_sub `update` ) {
        // nurlpkg update [<name>…] [--all|-y|--yes]
        : ( Vec String ) only ( vec_new [String] )
        : ~ i all 0
        : ~ i ai 2
        ~ < ai argc {
            : String a ( env_arg ai )
            : s a_s ( string_data a )
            ? | | != 0 ( nurl_str_eq a_s `--all` ) != 0 ( nurl_str_eq a_s `-y` ) != 0 ( nurl_str_eq a_s `--yes` ) {
                = all 1
                ( string_free a )
            } {
                ( vec_push [String] only a )
            }
            = ai + ai 1
        }
        : i rc ( __cmd_update only all )
        : i on ( vec_len [String] only )
        : ~ i ok 0
        ~ < ok on {
            : ?String oo ( vec_get [String] only ok )
            ?? oo {
                T s → ( string_free s )
                F _ → {}
            }
            = ok + ok 1
        }
        ( vec_free [String] only )
        ( string_free sub )
        ^ rc
    } {}
    ? != 0 ( nurl_str_eq s_sub `verify` ) {
        ( string_free sub )
        ^ ( __cmd_verify )
    } {}
    ? != 0 ( nurl_str_eq s_sub `test` ) {
        ( string_free sub )
        ^ ( __cmd_test )
    } {}
    ? != 0 ( nurl_str_eq s_sub `bench` ) {
        ( string_free sub )
        ^ ( __cmd_bench )
    } {}
    // `version` / `--version` are handled at the top of main (they print
    // the toolchain version) — no duplicate branches here.
    ? != 0 ( nurl_str_eq s_sub `help` ) {
        ( string_free sub )
        ( __print_usage )
        ^ 0
    } {}
    ( nurl_eprint `nurlpkg: unknown subcommand '` )
    ( nurl_eprint s_sub )
    ( nurl_eprintln `'` )
    ( string_free sub )
    ( __print_usage )
    ^ 2
}

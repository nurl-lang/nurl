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
$ `stdlib/ext/credentials.nu`
$ `stdlib/ext/json.nu`
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

@ __count_registry ( Vec Dep ) deps → i {
    : i n ( vec_len [Dep] deps )
    : ~ i c 0
    : ~ i k 0
    ~ < k n {
        : ?Dep dk ( vec_get [Dep] deps k )
        ?? dk { T d → { ? ( dep_is_registry d ) { = c + c 1 } {} } F → {} }
        = k + k 1
    }
    ^ c
}

// Build the X-Nurl-Deps JSON array of { name, req } from a manifest's
// REGISTRY dependencies (path deps are local and not part of the published
// package's index entry). Names/reqs are simple tokens (no JSON-special
// chars), so a direct build is safe. Empty deps → "[]".
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
                ? ( dep_is_registry d ) {
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
    ( nurl_print `  nurlpkg install <name> Fetch, build, and install a program from the registry onto $PATH.\n` )
    ( nurl_print `  nurlpkg lock           Regenerate nurl.lock from the current deps/ tree.\n` )
    ( nurl_print `  nurlpkg publish        Pack + upload this package to the registry.\n` )
    ( nurl_print `  nurlpkg login          Store a publish token in ~/.nurl/credentials.\n` )
    ( nurl_print `  nurlpkg logout [--revoke]  Forget the local token (and optionally revoke it).\n` )
    ( nurl_print `  nurlpkg search <q>     Search the registry for packages.\n` )
    ( nurl_print `  nurlpkg info <name>    Show a package's published versions.\n` )
    ( nurl_print `  nurlpkg yank|unyank <name> <version>  Hide/unhide a published version.\n` )
    ( nurl_print `  nurlpkg add <name> [--path P] [--version V]\n` )
    ( nurl_print `                         Add a dependency entry to nurl.toml.\n` )
    ( nurl_print `  nurlpkg remove <name>  Delete a dependency entry from nurl.toml.\n` )
    ( nurl_print `  nurlpkg verify         Check deps/ matches nurl.lock (names + versions); exit 1 if drift.\n` )
    ( nurl_print `  nurlpkg test           Build + run every tests/*.nu (exit 0 = pass; optional tests/outputs/ goldens).\n` )
    ( nurl_print `  nurlpkg bench          Build + run every benches/*.nu and stream their std/bench.nu reports.\n` )
    ( nurl_print `  nurlpkg version        Print the nurlpkg version.\n` )
    ( nurl_print `  nurlpkg help           Show this message.\n` )
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
    : b out ( string_eq t ( string_from `[dependencies]` ) )
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
    ? < tlen + nlen 1 { ^ F } {}
    : ~ i k 0
    ~ < k nlen {
        ? != ( nurl_str_get s k ) ( nurl_str_get name k ) { ^ F } {}
        = k + k 1
    }
    // After matching `<name>`, skip whitespace and require `=`.
    : ~ i p nlen
    ~ < p tlen {
        : i c ( nurl_str_get s p )
        ? | == c 32 == c 9 { = p + p 1 } {
            ^ == c 61
        }
    }
    ^ F
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
        T s → = src s
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
        T s → = src s
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
@ __install_registry Manifest m ( Vec LockPkg ) out → i {
    ? == ( __count_registry . m dependencies ) 0 { ^ 0 } {}
    : String reg ( __registry_url m )
    ( nurl_print `resolving registry dependencies against ` )
    ( nurl_print ( string_data reg ) )
    ( nurl_print `\n` )
    : ( @ String s ) fetch \ s nm → String { ^ ( pkg_fetch_index ( string_data reg ) nm ) }
    : ~ i rc 0
    : !( Vec LockPkg ) ResolveErr rr ( resolve_registry . m dependencies ( string_data reg ) fetch )
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
    ^ rc
}

// ── login / logout ───────────────────────────────────────────────

@ __cmd_login → i {
    : String reg ( __reg_default )
    ( nurl_print `Registry: ` ) ( nurl_print ( string_data reg ) ) ( nurl_print `\n` )
    ( nurl_print `Paste a publish token (get one at <registry>/login): ` )
    : String token ( read_line )
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
@ __cmd_publish → i {
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
            ? == ( string_len token ) 0 {
                ( nurl_eprintln `nurlpkg: no auth token — run 'nurlpkg login' or set $NURL_TOKEN` )
                = rc 1
            } {
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
                        ( nurl_print `publishing ` )
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
                        : String deps_json ( __deps_json m )
                        : !i PublishErr ur ( pkg_publish ( string_data reg ) ( string_data token ) tarball ( string_data . m name ) ( string_data . m version ) ( string_data deps_json ) )
                        ( string_free deps_json )
                        ?? ur {
                            T _ → ( nurl_print `published.\n` )
                            F ue → {
                                ( nurl_eprint `nurlpkg: publish failed (` )
                                ( nurl_eprint ( publish_err_name ue ) )
                                ( nurl_eprintln `)` )
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
//
// This is the payoff of the installable toolchain: an outside user runs
// `nurlpkg install argz-demo` and gets a working program built from
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

// pkgdir (absolute) holds the unpacked package (nurl.toml + src/main.nu).
// Resolve its deps in-process, build the entry point, and install the
// binary into bindir/name. Cross-platform: uses fs primitives + a
// shell-free driver spawn, no POSIX coreutils.
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
                ( nurl_print `Installed ` ) ( nurl_print name )
                ( nurl_print ` → ` ) ( nurl_print ( string_data dest ) ) ( nurl_print `\n` )
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
                                    ( nurl_eprint `nurlpkg: '` ) ( nurl_eprint name )
                                    ( nurl_eprintln `' is a library, not an installable program (no src/main.nu)` )
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
            : i reg_rc ( __install_registry root regpkgs )
            ? != reg_rc 0 { = rc 1 } {}
            ( manifest_free root )
            // Regenerate the lockfile from the resulting deps/ tree. We do
            // this even if some deps failed — a partial lockfile correctly
            // reflects what's actually installed. Registry entries carry
            // their resolved source + tarball checksum.
            : i lr ( __write_lockfile regpkgs )
            ? != lr 0 { = rc 1 } {}
            ( lockpkgs_free regpkgs )
            ( nurl_print `done.\n` )
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
// The build driver is `./nurl.sh` by default; override with $NURL_CC
// (a command taking `<flags> <src> <outbin>`), e.g. a wrapper around an
// installed `nurl`. Test binaries land in /tmp.

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
    ^ ?? ( env_get `NURL_CC` ) {
        T v → v
        F _ → { : String d ( string_with_cap 16 ) ( string_push_str d `./nurl.sh` ) d }
    }
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
// default ./nurl.sh).

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

// ── dispatch ─────────────────────────────────────────────────────

@ main → i {
    : i argc ( env_args_count )
    ? < argc 2 {
        ( __print_usage )
        ^ 0
    } {}
    : String sub ( env_arg 1 )
    : s s_sub ( string_data sub )
    ? | != 0 ( nurl_str_eq s_sub `--version` ) != 0 ( nurl_str_eq s_sub `version` ) {
        ( nurl_print ( nurl_version ) ) ( nurl_print `\n` )
        ( string_free sub )
        ^ 0
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
        ^ ( __cmd_lock )
    } {}
    ? != 0 ( nurl_str_eq s_sub `publish` ) {
        ( string_free sub )
        ^ ( __cmd_publish )
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
    ? != 0 ( nurl_str_eq s_sub `version` ) {
        ( string_free sub )
        ( nurl_print `nurlpkg 0.6.1\n` )
        ^ 0
    } {}
    // Accept --version as the conventional spelling too.
    ? != 0 ( nurl_str_eq s_sub `--version` ) {
        ( string_free sub )
        ( nurl_print `nurlpkg 0.6.1\n` )
        ^ 0
    } {}
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

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
$ `stdlib/ext/env.nu`
$ `stdlib/ext/manifest.nu`

// ── usage ────────────────────────────────────────────────────────

@ __print_usage → v {
    ( nurl_print `nurlpkg — NURL package manager\n\n` )
    ( nurl_print `Usage:\n` )
    ( nurl_print `  nurlpkg init <name>    Create a new nurl.toml in the current directory.\n` )
    ( nurl_print `  nurlpkg info           Print the parsed manifest in the current directory.\n` )
    ( nurl_print `  nurlpkg deps           List dependencies, one per line.\n` )
    ( nurl_print `  nurlpkg install        Resolve path-deps and symlink them under ./deps/.\n` )
    ( nurl_print `  nurlpkg lock           Regenerate nurl.lock from the current deps/ tree.\n` )
    ( nurl_print `  nurlpkg add <name> [--path P] [--version V]\n` )
    ( nurl_print `                         Add a dependency entry to nurl.toml.\n` )
    ( nurl_print `  nurlpkg remove <name>  Delete a dependency entry from nurl.toml.\n` )
    ( nurl_print `  nurlpkg verify         Check deps/ matches nurl.lock (names + versions); exit 1 if drift.\n` )
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
        ( nurl_eprint `  ` )
        ( nurl_eprint name )
        ( nurl_eprintln `: skip (no path; registry deps are not supported in v1)` )
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
        // Without lstat/readlink primitives we can't verify the
        // existing entry points where we expect. v1: treat any
        // existing entry as already-installed so `nurlpkg install`
        // is idempotent. Name collisions across transitive deps
        // will land here too — surface in the deps listing instead.
        ( nurl_print `  ` ) ( nurl_print name )
        ( nurl_print ` (already installed)\n` )
        // Record it as seen so the transitive walker doesn't try
        // to re-process the same target.
        ( vec_push [String] seen ( string_from target_s ) )
        ( string_free linkpath )
        ( string_free target )
        ^ 0
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
@ __write_lockfile → i {
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
                            : String src ( string_from `deps/` )
                            ( string_push_str src ( string_data name ) )
                            ( __lock_kv_str body `source` ( string_data src ) )
                            ( string_free src )
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
    : i rc ( __write_lockfile )
    ? == rc 0 { ( nurl_print `wrote nurl.lock\n` ) } {}
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
            : ( Vec String ) next_queue ( vec_new [String] )
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
            ( manifest_free root )
            // Regenerate the lockfile from the resulting deps/ tree.
            // We do this even if some deps failed — a partial
            // lockfile correctly reflects what's actually installed.
            : i lr ( __write_lockfile )
            ? != lr 0 { = rc 1 } {}
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

// ── dispatch ─────────────────────────────────────────────────────

@ main → i {
    : i argc ( env_args_count )
    ? < argc 2 {
        ( __print_usage )
        ^ 0
    } {}
    : String sub ( env_arg 1 )
    : s s_sub ( string_data sub )
    ? != 0 ( nurl_str_eq s_sub `init` ) {
        : String name ? >= argc 3 ( env_arg 2 ) ( string_new )
        : i rc ( __cmd_init ( string_data name ) )
        ( string_free name )
        ( string_free sub )
        ^ rc
    } {}
    ? != 0 ( nurl_str_eq s_sub `info` ) {
        ( string_free sub )
        ^ ( __cmd_info )
    } {}
    ? != 0 ( nurl_str_eq s_sub `deps` ) {
        ( string_free sub )
        ^ ( __cmd_deps )
    } {}
    ? != 0 ( nurl_str_eq s_sub `install` ) {
        ( string_free sub )
        ^ ( __cmd_install )
    } {}
    ? != 0 ( nurl_str_eq s_sub `lock` ) {
        ( string_free sub )
        ^ ( __cmd_lock )
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

// stdlib/ext/manifest.nu — typed view over `nurl.toml` package manifests.
//
// Layered on top of `stdlib/ext/toml.nu`: parse the raw TOML, then
// pull out the well-known fields into a typed `Manifest` struct. The
// raw TomlValue can still be carried alongside for tooling that needs
// to inspect unknown fields (e.g. linter or schema validator).
//
// Manifest schema (Cargo-shaped):
//
//   [package]
//   name = "demo"               # required
//   version = "0.1.0"           # required
//   description = "..."         # optional
//   license = "MIT"             # optional
//   registry = "https://..."    # optional: default registry for bare deps
//   authors = ["A", "B"]        # optional (not yet exposed on Manifest)
//
//   [dependencies]
//   foo = { path = "../foo", version = "0.2.0" }   # path dependency
//   bar = "^1.2"                                    # registry dep (default registry)
//   baz = { version = "1.0", registry = "https://reg.example/" }  # explicit registry
//
// A dependency is a PATH dep when `path` is non-empty, otherwise a
// REGISTRY dep whose `version` is a semver requirement (see
// `stdlib/ext/semver.nu`) resolved against `registry` (or, when empty,
// the manifest's `[package].registry`, or the tool's built-in default).
// Use `dep_is_path` / `dep_is_registry` to discriminate.
//
// Scope:
//   * Single [dependencies] section (no dev-dependencies / target.*).
//   * No workspace support.
//
// API:
//
//   ( manifest_parse s src s path_for_diag ) → ! Manifest ManifestErr
//   ( manifest_load s path )                  → ! Manifest ManifestErr
//   ( manifest_free Manifest m )              → v
//   ( dep_free Dep d )                        → v
//   ( dep_is_path Dep d )  / ( dep_is_registry Dep d ) → b
//   ( manifest_err_name ManifestErr e )       → s

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/toml.nu`

: Dep {
    String name
    String path  // non-empty → path dependency
    String version  // semver requirement (registry dep) or pinned version
    String registry  // registry URL; empty → manifest/tool default
}

: Manifest {
    String name
    String version
    String description
    String license
    String registry  // default registry URL for bare deps; empty → tool default
    String repository  // [package].repository — source URL; empty → unset
    String postinstall  // [hints].postinstall — message shown after install; empty → none
    ( Vec Dep ) dependencies
}

: | ManifestErr {
    ManifestReadFailed  // file_read returned empty / nurl_read_file failed
    ManifestParseFailed  // TOML didn't parse
    ManifestMissingName  // [package].name missing
    ManifestMissingVersion  // [package].version missing
    ManifestBadShape  // dependencies entry isn't a string or inline table
}

@ manifest_err_name ManifestErr e → s {
    ^ ?? e {
        ManifestReadFailed → `ManifestReadFailed`
        ManifestParseFailed → `ManifestParseFailed`
        ManifestMissingName → `ManifestMissingName`
        ManifestMissingVersion → `ManifestMissingVersion`
        ManifestBadShape → `ManifestBadShape`
    }
}

// ── Cascade-free helpers ─────────────────────────────────────────

@ dep_free Dep d → v {
    ( string_free . d name )
    ( string_free . d path )
    ( string_free . d version )
    ( string_free . d registry )
}

// A dependency resolved from a local path (`path` set) vs. fetched from
// a registry by semver requirement (`path` empty).
@ dep_is_path Dep d → b {
    ^ > ( string_len . d path ) 0
}

@ dep_is_registry Dep d → b {
    ^ == ( string_len . d path ) 0
}

// A dependency carries a registry version requirement. Cargo-style
// `{ path = "...", version = "..." }` hybrids set BOTH: `path` is a
// local-development override, `version` is the requirement used when the
// package is published or installed from the registry (i.e. when the
// local path is unavailable). Such hybrids are `dep_is_path` (a path is
// set) yet still registry-publishable / registry-resolvable.
@ dep_has_version Dep d → b {
    ^ > ( string_len . d version ) 0
}

@ manifest_free Manifest m → v {
    ( string_free . m name )
    ( string_free . m version )
    ( string_free . m description )
    ( string_free . m license )
    ( string_free . m repository )
    ( string_free . m postinstall )
    ( string_free . m registry )
    : i n ( vec_len [Dep] . m dependencies )
    : ~ i k 0
    ~ < k n {
        : ?Dep dk ( vec_get [Dep] . m dependencies k )
        ?? dk {
            T dv → ( dep_free dv )
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free [Dep] . m dependencies )
}

// ── Field extraction helpers ─────────────────────────────────────
//
// `__field_str` returns an OWNED String — empty when the path is
// missing or the value isn't a string. Use `string_len` (NOT
// `nurl_str_len` — that one expects a raw `i8*` and silently
// misreads a `String` struct as a pointer to the wrong bytes).

@ __field_str TomlValue root s path → String {
    : ~ String out ( string_new )
    : ?TomlValue v ( toml_get_path root path )
    ?? v {
        T tv → {
            : ?String s ( toml_as_str tv )
            ?? s {
                T sv → { ( string_free out ) = out sv }
                F empty → ( string_free empty )
            }
        }
        F _ → {}
    }
    ^ out
}

// ── Dep extraction ──────────────────────────────────────────────
//
// `[dependencies]` is a TTable whose entries are either:
//   * Inline table: `name = { path = "...", version = "..." }`
//   * Bare string : `name = "1.2.3"` (version-only, path absent)
//
// The bare-string form maps to a Dep with empty `path` — the caller
// (resolver) treats this as an error since the MVP only supports
// path-based deps. We accept the shape here so the parser doesn't
// reject manifests early.

// Parameter must not be named `entry` because LLVM reserves that
// identifier for every function's entry block — the resulting
// `%entry` register collides with `entry:` and refuses to emit.
@ __dep_from_entry TomlEntry ent → !Dep ManifestErr {
    : String name ( string_from ( string_data . ent key ) )
    : ~ String path ( string_new )
    : ~ String version ( string_new )
    : ~ String registry ( string_new )
    ?? . ent value {
        TStr sv → {
            // Bare version string → registry dep against the default
            // registry. Copy as version, leave path + registry empty.
            ( string_free version )
            = version ( string_from ( string_data sv ) )
        }
        TTable _ → {
            // Inline table form — pull path + version + registry.
            : ?TomlValue pv ( toml_get . ent value `path` )
            ?? pv {
                T pj → {
                    : ?String ps ( toml_as_str pj )
                    ?? ps {
                        T s → { ( string_free path ) = path s }
                        F empty → ( string_free empty )
                    }
                }
                F _ → {}
            }
            : ?TomlValue vv ( toml_get . ent value `version` )
            ?? vv {
                T vj → {
                    : ?String vs ( toml_as_str vj )
                    ?? vs {
                        T s → { ( string_free version ) = version s }
                        F empty → ( string_free empty )
                    }
                }
                F _ → {}
            }
            : ?TomlValue rv ( toml_get . ent value `registry` )
            ?? rv {
                T rj → {
                    : ?String rs ( toml_as_str rj )
                    ?? rs {
                        T s → { ( string_free registry ) = registry s }
                        F empty → ( string_free empty )
                    }
                }
                F _ → {}
            }
        }
        _ → {
            ( string_free name )
            ( string_free path )
            ( string_free version )
            ( string_free registry )
            ^ @ !Dep ManifestErr { F # ManifestErr ManifestBadShape }
        }
    }
    ^ @ !Dep ManifestErr { T @ Dep { name path version registry } }
}

// ── Top-level parser ─────────────────────────────────────────────

@ manifest_parse s src s path_for_diag → !Manifest ManifestErr {
    : !TomlValue TomlErr tr ( toml_parse src )
    ?? tr {
        F _ → ^ @ !Manifest ManifestErr { F # ManifestErr ManifestParseFailed }
        T root → {
            // Required fields.
            : String name ( __field_str root `package.name` )
            ? == 0 ( string_len name ) {
                ( string_free name )
                ( toml_value_free root )
                ^ @ !Manifest ManifestErr { F # ManifestErr ManifestMissingName }
            } {}
            : String version ( __field_str root `package.version` )
            ? == 0 ( string_len version ) {
                ( string_free name )
                ( string_free version )
                ( toml_value_free root )
                ^ @ !Manifest ManifestErr { F # ManifestErr ManifestMissingVersion }
            } {}
            // Optional fields.
            : String description ( __field_str root `package.description` )
            : String license ( __field_str root `package.license` )
            : String registry ( __field_str root `package.registry` )
            : String repository ( __field_str root `package.repository` )
            : String postinstall ( __field_str root `hints.postinstall` )

            // Dependencies.
            : ( Vec Dep ) deps ( vec_new [Dep] )
            : ?TomlValue dt ( toml_get root `dependencies` )
            ?? dt {
                T dt_v → {
                    ?? dt_v {
                        TTable entries → {
                            : i ne ( vec_len [TomlEntry] entries )
                            : ~ i k 0
                            ~ < k ne {
                                : ?TomlEntry ek ( vec_get [TomlEntry] entries k )
                                ?? ek {
                                    T ev → {
                                        : !Dep ManifestErr dr ( __dep_from_entry ev )
                                        ?? dr {
                                            T d → ( vec_push [Dep] deps d )
                                            F _ → {}
                                        }
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
            ( toml_value_free root )
            ^ @ !Manifest ManifestErr { T @ Manifest { name version description license registry repository postinstall deps } }
        }
    }
}

// Read `path` from disk and parse it. Returns ManifestReadFailed when
// the file can't be read OR is empty.
@ manifest_load s path → !Manifest ManifestErr {
    : s raw ( nurl_read_file path )
    ? == 0 ( nurl_str_len raw ) {
        ^ @ !Manifest ManifestErr { F # ManifestErr ManifestReadFailed }
    } {}
    ^ ( manifest_parse raw path )
}

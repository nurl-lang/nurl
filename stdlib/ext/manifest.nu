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
//   nurl-version = "0.65.0"     # optional minimum toolchain (SemVer)
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
//   ( manifest_free Manifest m )              → v   early release (optional)
//   ( dep_free Dep d )                        → v   early release (optional)
//   ( dep_is_path Dep d )  / ( dep_is_registry Dep d ) → b
//   ( manifest_err_name ManifestErr e )       → s

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/toml.nu`
$ `stdlib/ext/semver.nu`

: Dep {
    String name
    String path  // non-empty → path dependency
    String version  // semver requirement (registry dep) or pinned version
    String registry  // registry URL; empty → manifest/tool default
}

: Manifest {
    String name
    String version
    String nurl_version  // minimum compiler/stdlib/runtime release; empty → unrestricted
    String description
    String license
    String registry  // default registry URL for bare deps; empty → tool default
    String repository  // [package].repository — source URL; empty → unset
    String postinstall  // [hints].postinstall — message shown after install; empty → none
    ( Vec Dep ) dependencies
    ( Vec String ) assets  // [install].assets — package-relative paths staged under $NURL_HOME/share/<name>/ on tool install
}

: | ManifestErr {
    ManifestReadFailed  // the manifest could not be read, or is empty
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

// Let go of `d` now rather than at the end of its owner's scope.
@ dep_free sink Dep d → v {}

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

// Let go of `m` now rather than at the end of its owner's scope.
@ manifest_free sink Manifest m → v {}

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
                T sv → { = out sv }
                F empty → {}
            }
        }
        F _ → {}
    }
    ^ out
}

// Read a dotted `path` expected to hold an array of strings, returning an
// OWNED Vec[String] (its elements each owned). Missing path, non-array
// value, or non-string elements yield an empty vector; non-string elements
// are skipped. `toml_get_path` borrows into `root`, so we copy each string
// out (toml_as_str returns an owned copy) and never free the borrowed nodes.
@ __field_str_array TomlValue root s path → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : ?TomlValue v ( toml_get_path root path )
    ?? v {
        T tv → {
            ?? tv {
                TArr arr → {
                    : i n ( vec_len [TomlValue] arr )
                    : ~ i k 0
                    ~ < k n {
                        : ?TomlValue ek ( vec_get [TomlValue] arr k )
                        ?? ek {
                            T ev → {
                                : ?String sv ( toml_as_str ev )
                                ?? sv {
                                    T s → ( vec_push [String] out s )
                                    F empty → {}
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
            = version ( string_from ( string_data sv ) )
        }
        TTable _ → {
            // Inline table form — pull path + version + registry.
            : ?TomlValue pv ( toml_get . ent value `path` )
            ?? pv {
                T pj → {
                    : ?String ps ( toml_as_str pj )
                    ?? ps {
                        T s → { = path s }
                        F empty → {}
                    }
                }
                F _ → {}
            }
            : ?TomlValue vv ( toml_get . ent value `version` )
            ?? vv {
                T vj → {
                    : ?String vs ( toml_as_str vj )
                    ?? vs {
                        T s → { = version s }
                        F empty → {}
                    }
                }
                F _ → {}
            }
            : ?TomlValue rv ( toml_get . ent value `registry` )
            ?? rv {
                T rj → {
                    : ?String rs ( toml_as_str rj )
                    ?? rs {
                        T s → { = registry s }
                        F empty → {}
                    }
                }
                F _ → {}
            }
        }
        _ → {
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
                ^ @ !Manifest ManifestErr { F # ManifestErr ManifestMissingName }
            } {}
            : String version ( __field_str root `package.version` )
            ? == 0 ( string_len version ) {
                ^ @ !Manifest ManifestErr { F # ManifestErr ManifestMissingVersion }
            } {}
            // Optional fields.
            : String nurl_min ( __field_str root `package.nurl-version` )
            : ~ b min_valid T
            ?? ( toml_get_path root `package.nurl-version` ) {
                T value → { ?? value {
                        TStr _ → { ? == ( string_len nurl_min ) 0 { = min_valid F } {} }
                        _ → { = min_valid F }
                    } }
                F _ → {}
            }
            ? > ( string_len nurl_min ) 0 {
                ?? ( semver_parse ( string_data nurl_min ) ) {
                    T parsed → {}
                    F _ → { = min_valid F }
                }
            } {}
            ? ! min_valid {
                ^ @ !Manifest ManifestErr { F ManifestBadShape }
            } {}
            : String description ( __field_str root `package.description` )
            : String license ( __field_str root `package.license` )
            : String registry ( __field_str root `package.registry` )
            : String repository ( __field_str root `package.repository` )
            : String postinstall ( __field_str root `hints.postinstall` )
            : ( Vec String ) assets ( __field_str_array root `install.assets` )

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
            ^ @ !Manifest ManifestErr { T @ Manifest { name version nurl_min description license registry repository postinstall deps assets } }
        }
    }
}

// Is the toolchain at least the package's `package.nurl-version`?
// Advisory only: nurlpkg calls this nowhere, and no install or publish is
// refused on its answer (docs/TOOLING.md). It is kept for tools that want
// to print a hint, with the rules a hint should follow:
//
// The answer is F only when the toolchain's version is KNOWN and strictly
// older. A requirement check that cannot tell is not evidence of an old
// toolchain, and refusing on it turned a lookup bug into "nothing installs"
// (a Windows install found no compiler where it looked, read an empty
// version, and refused every package). So:
//
//   * an empty or unparseable toolchain version (`unknown`, a bare SHA)
//     and the build scripts' `v0.0.0` no-version fallback are accepted;
//   * a `git describe` dev build — `v0.71.0-3-gabc1234`, `v0.71.0-dirty`,
//     `v0.71.0-3-gabc1234-dirty` — is the tag plus later commits, so it
//     compares as its tag (0.71.0), not as a 0.71.0 prerelease;
//   * a leading `v` and surrounding whitespace (CRLF from a Windows pipe)
//     are ignored; otherwise SemVer precedence, real prereleases included
//     (0.65.0-rc.1 is older than 0.65.0).
@ __mf_all_digits s text i from i to → b {
    ? >= from to { ^ F } {}
    : ~ i k from
    ~ < k to {
        : i c ( nurl_str_get text k )
        ? | < c 48 > c 57 { ^ F } {}
        = k + k 1
    }
    ^ T
}

@ __mf_all_hex s text i from i to → b {
    ? >= from to { ^ F } {}
    : ~ i k from
    ~ < k to {
        : i c ( nurl_str_get text k )
        : b digit & >= c 48 <= c 57
        : b lower & >= c 97 <= c 102
        : b upper & >= c 65 <= c 70
        ? ! | | digit lower upper { ^ F } {}
        = k + k 1
    }
    ^ T
}

// Length of `text` with a trailing `git describe` suffix removed:
// `-dirty`, then `-<commits>-g<hex sha>`.
@ __toolchain_describe_core_len s text i n → i {
    : ~ i end n
    ? >= end 6 {
        : b dirty & & & & & == ( nurl_str_get text - end 6 ) 45
        == ( nurl_str_get text - end 5 ) 100 == ( nurl_str_get text - end 4 ) 105
        == ( nurl_str_get text - end 3 ) 114 == ( nurl_str_get text - end 2 ) 116
        == ( nurl_str_get text - end 1 ) 121
        ? dirty { = end - end 6 } {}
    } {}
    // last '-' before end: start of the -g<sha> part
    : ~ i g - end 1
    ~ & >= g 0 != ( nurl_str_get text g ) 45 { = g - g 1 }
    ? & > g 0 & < + g 1 end == ( nurl_str_get text + g 1 ) 103 {
        ? ( __mf_all_hex text + g 2 end ) {
            : ~ i c - g 1
            ~ & >= c 0 != ( nurl_str_get text c ) 45 { = c - c 1 }
            ? & > c 0 ( __mf_all_digits text + c 1 g ) { = end c } {}
        } {}
    } {}
    ^ end
}

@ manifest_supports_toolchain Manifest manifest s actual → b {
    ? == ( string_len . manifest nurl_version ) 0 { ^ T } {}
    : String raw ( string_from actual )
    : String trimmed ( string_trim raw )
    : ~ i from 0
    ? > ( string_len trimmed ) 0 {
        ? == ( string_get trimmed 0 ) 118 { = from 1 } {}
    } {}
    : i n - ( string_len trimmed ) from
    : String rest ( string_substr trimmed from n )
    : i core ( __toolchain_describe_core_len ( string_data rest ) n )
    : String version ( string_substr rest 0 core )
    : ~ b supported T
    ?? ( semver_parse ( string_data version ) ) {
        F _ → {}
        T current → {
            : b unknown & & == . current major 0 == . current minor 0 == . current patch 0
            ? ! unknown {
                ?? ( semver_parse ( string_data . manifest nurl_version ) ) {
                    F _ → {}
                    T required → {
                        = supported >= ( semver_compare current required ) 0
                    }
                }
            } {}
        }
    }
    ^ supported
}

// Read `path` from disk and parse it. Returns ManifestReadFailed when
// the file can't be read OR is empty.
@ manifest_load s path → !Manifest ManifestErr {
    ?? ( read_file path ) {
        F _ → { ^ @ !Manifest ManifestErr { F ManifestReadFailed } }
        T text → {
            : ~ ! Manifest ManifestErr result @ !Manifest ManifestErr { F ManifestReadFailed }
            ? > ( string_len text ) 0 {
                ? == ( string_len text ) ( nurl_str_len ( string_data text ) ) {
                    = result ( manifest_parse ( string_data text ) path )
                } {
                    = result @ !Manifest ManifestErr { F ManifestParseFailed }
                }
            } {}
            ^ result
        }
    }
}

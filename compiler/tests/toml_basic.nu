// toml_basic.nu — round-trip parse a Cargo-shaped manifest + lockfile.
//
// Covers every TOML 1.0 feature that stdlib/ext/toml.nu actually
// supports:
//
//   * Top-level [package] section + dotted path lookups
//   * String values with `\n` and `\"` escapes
//   * Signed integer values (positive + negative)
//   * Boolean values
//   * Bare arrays of strings
//   * Inline tables for [dependencies] entries
//   * [[package]] array-of-tables (lockfile shape)
//   * `#` comments to end of line
//
// Offline (no network gate). Default snapshot captures the
// extracted field values so any future parser regression shows up
// as a baseline diff.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/toml.nu`

@ show_str s label TomlValue v → v {
    ( nurl_print label )
    ( nurl_print `=` )
    : ?String r ( toml_as_str v )
    ?? r {
        T s → {
            ( nurl_print ( string_data s ) )
            ( nurl_print `\n` )
            ( string_free s )
        }
        F _ → ( nurl_print `<not-string>\n` )
    }
}

@ show_int s label TomlValue v → v {
    ( nurl_print label )
    ( nurl_print `=` )
    : ?i r ( toml_as_int v )
    ?? r {
        T n → {
            ( nurl_print ( nurl_str_int n ) )
            ( nurl_print `\n` )
        }
        F _ → ( nurl_print `<not-int>\n` )
    }
}

@ show_bool s label TomlValue v → v {
    ( nurl_print label )
    ( nurl_print `=` )
    : ?b r ( toml_as_bool v )
    ?? r {
        T x → ( nurl_print ? x `T\n` `F\n` )
        F _ → ( nurl_print `<not-bool>\n` )
    }
}

@ probe s label TomlValue root s path i kind → v {
    : ?TomlValue r ( toml_get_path root path )
    ?? r {
        T v → {
            ? == kind 0 { ( show_str label v ) } {}
            ? == kind 1 { ( show_int label v ) } {}
            ? == kind 2 { ( show_bool label v ) } {}
        }
        F _ → {
            ( nurl_print label ) ( nurl_print `=<missing>\n` )
        }
    }
}

@ main → i {
    : s manifest
    `# nurl.toml — package manifest
[package]
name = "demo"
version = "0.4.4"
edition = -1
license = "MIT OR Apache-2.0"
authors = ["Tero <t@example.com>", "Other"]
publishable = true

[dependencies]
http-router = { path = "../router", version = "0.2.0" }
some-lib = { path = "../some-lib" }
msg = "hello \"world\"\n"
`

    : !TomlValue TomlErr r ( toml_parse manifest )
    ?? r {
        F e → {
            ( nurl_print `parse_err=` )
            ( nurl_print ( toml_err_name e ) )
            ( nurl_print `\n` )
            ^ 1
        }
        T root → {
            ( probe `name` root `package.name` 0 )
            ( probe `version` root `package.version` 0 )
            ( probe `license` root `package.license` 0 )
            ( probe `edition` root `package.edition` 1 )
            ( probe `publishable` root `package.publishable` 2 )
            ( probe `escaped` root `dependencies.msg` 0 )
            ( probe `router_path` root `dependencies.http-router.path` 0 )
            ( probe `router_ver` root `dependencies.http-router.version` 0 )
            ( probe `some_path` root `dependencies.some-lib.path` 0 )

            // Array-of-strings extraction.
            : ?TomlValue ar ( toml_get_path root `package.authors` )
            ?? ar {
                T av → {
                    ?? av {
                        TArr items → {
                            ( nurl_print `authors_count=` )
                            ( nurl_print ( nurl_str_int ( vec_len [TomlValue] items ) ) )
                            ( nurl_print `\n` )
                            : ?TomlValue a0 ( vec_get [TomlValue] items 0 )
                            ?? a0 {
                                T v → ( show_str `authors[0]` v )
                                F _ → {}
                            }
                        }
                        _ → ( nurl_print `authors=<not-array>\n` )
                    }
                }
                F _ → ( nurl_print `authors=<missing>\n` )
            }

            ( toml_value_free root )
        }
    }

    // Now a lockfile-shape input with [[package]] array-of-tables.
    ( nurl_print `\n-- lockfile --\n` )
    : s lockfile
    `# nurl.lock — auto-generated
[[package]]
name = "http-router"
version = "0.2.0"
source = "path+file:///abs/path/to/router"

[[package]]
name = "some-lib"
version = "1.0.0"
source = "path+file:///abs/path/to/some-lib"
`

    : !TomlValue TomlErr lr ( toml_parse lockfile )
    ?? lr {
        F e → {
            ( nurl_print `lockfile_err=` )
            ( nurl_print ( toml_err_name e ) )
            ( nurl_print `\n` )
        }
        T lroot → {
            : ?TomlValue pkgs ( toml_get lroot `package` )
            ?? pkgs {
                T pkv → {
                    ?? pkv {
                        TArr items → {
                            : i np ( vec_len [TomlValue] items )
                            ( nurl_print `pkg_count=` )
                            ( nurl_print ( nurl_str_int np ) )
                            ( nurl_print `\n` )
                            : ~ i k 0
                            ~ < k np {
                                : ?TomlValue pk_o ( vec_get [TomlValue] items k )
                                ?? pk_o {
                                    T pkg → {
                                        ( nurl_print `pkg[` )
                                        ( nurl_print ( nurl_str_int k ) )
                                        ( nurl_print `].name=` )
                                        : ?TomlValue nm ( toml_get pkg `name` )
                                        ?? nm {
                                            T nv → ( show_str `` nv )
                                            F _ → ( nurl_print `<missing>\n` )
                                        }
                                    }
                                    F _ → {}
                                }
                                = k + k 1
                            }
                        }
                        _ → ( nurl_print `package=<not-array>\n` )
                    }
                }
                F _ → ( nurl_print `package=<missing>\n` )
            }
            ( toml_value_free lroot )
        }
    }
    ^ 0
}

// mermaid-server/src/theme.nu — templates: the look, loaded from outside.
//
// The renderer holds no colours, no fonts and no spacing of its own. Every
// value it draws with comes from a TEMPLATE — a TOML file read from an
// external source at startup — looked up by a dotted key:
//
//     canvas.background   layout.rank_gap   node.fill   node.diamond.fill
//
// A theme is therefore just a flat key → string store: the TOML tree is
// flattened on load, and the renderer asks for `node.<shape>.<key>` and
// falls back to `node.<key>`. Adding a look means dropping a file in the
// template directory; adding a *knob* means one `mmd_theme_*` call in the
// renderer plus a line of documentation. Neither needs a new type.
//
// Values are stored as strings because that is what SVG consumes. TOML has
// no float in this stdlib, so a non-integer (`stroke_width = "1.5"`) is
// written quoted and travels through verbatim; the integer accessor parses
// on demand for the values layout needs as numbers.
//
// `MmdTemplateSet.kind` is the source discriminator. Only
// `MMD_TSRC_DIR` (a filesystem directory) exists today; a registry- or
// HTTP-backed source becomes a second `kind` and a second branch in
// `mmd_templates_load`, with nothing else in the program changing.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/ext/toml.nu`

: i MMD_TSRC_DIR 0

// ── Theme: a flat dotted-key store ───────────────────────────────────

: MmdKV {
    String key
    String val
}

: MmdTheme {
    String name
    String desc
    ( Vec MmdKV ) kv
}

@ mmd_theme_new s name → MmdTheme {
    ^ @ MmdTheme { ( string_from name ) ( string_new ) ( vec_new [MmdKV] ) }
}

@ mmd_theme_free MmdTheme t → v {
    ( string_free . t name )
    ( string_free . t desc )
    : i n ( vec_len [MmdKV] . t kv )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [MmdKV] . t kv i ) {
            T e → {
                ( string_free . e key )
                ( string_free . e val )
            }
            F _ → {}
        }
        = i + i 1
    }
    ( vec_free [MmdKV] . t kv )
}

// Last write wins, so a `[node.diamond]` table may restate a key set in
// `[node]`.
@ mmd_theme_set MmdTheme t s key s val → v {
    : i n ( vec_len [MmdKV] . t kv )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [MmdKV] . t kv i ) {
            T e → {
                ? != 0 ( nurl_str_eq ( string_data . e key ) key ) {
                    ( string_clear . e val )
                    ( string_push_str . e val val )
                    ^ v
                } {}
            }
            F _ → {}
        }
        = i + i 1
    }
    : MmdKV e @ MmdKV { ( string_from key ) ( string_from val ) }
    ( vec_push [MmdKV] . t kv e )
}

// The stored value, or `deflt`. BORROWS: the returned pointer is valid
// while the theme is.
@ mmd_theme_str MmdTheme t s key s deflt → s {
    : i n ( vec_len [MmdKV] . t kv )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [MmdKV] . t kv i ) {
            T e → {
                ? != 0 ( nurl_str_eq ( string_data . e key ) key ) {
                    ^ ( string_data . e val )
                } {}
            }
            F _ → {}
        }
        = i + i 1
    }
    ^ deflt
}

// A sentinel that no template can produce, so "absent" is distinguishable
// from "present and empty".
@ __mmdt_missing → s { ^ `\x00__mmd_absent__` }

@ mmd_theme_has MmdTheme t s key → b {
    ^ == 0 ( nurl_str_eq ( mmd_theme_str t key ( __mmdt_missing ) ) ( __mmdt_missing ) )
}

@ mmd_theme_int MmdTheme t s key i deflt → i {
    : s raw ( mmd_theme_str t key `` )
    ? == ( nurl_str_len raw ) 0 { ^ deflt } {}
    ^ ( nurl_str_to_int raw )
}

// `<prefix>.<variant>.<key>` if present, else `<prefix>.<key>`, else
// `deflt`. This two-step is what makes a template able to restyle one
// shape (or one line style) without restating the rest.
@ mmd_theme_var_str MmdTheme t s prefix s variant s key s deflt → s {
    : String k ( string_with_cap 48 )
    ( string_push_str k prefix )
    ( string_push_str k `.` )
    ( string_push_str k variant )
    ( string_push_str k `.` )
    ( string_push_str k key )
    : b hit ( mmd_theme_has t ( string_data k ) )
    : ~ s out deflt
    ? hit { = out ( mmd_theme_str t ( string_data k ) deflt ) } {
        ( string_clear k )
        ( string_push_str k prefix )
        ( string_push_str k `.` )
        ( string_push_str k key )
        = out ( mmd_theme_str t ( string_data k ) deflt )
    }
    ( string_free k )
    ^ out
}

@ mmd_theme_var_int MmdTheme t s prefix s variant s key i deflt → i {
    : s raw ( mmd_theme_var_str t prefix variant key `` )
    ? == ( nurl_str_len raw ) 0 { ^ deflt } {}
    ^ ( nurl_str_to_int raw )
}

// ── TOML → theme ─────────────────────────────────────────────────────

@ __mmdt_join s prefix s key → String {
    : String out ( string_with_cap 48 )
    ? > ( nurl_str_len prefix ) 0 {
        ( string_push_str out prefix )
        ( string_push_str out `.` )
    } {}
    ( string_push_str out key )
    ^ out
}

@ __mmdt_scalar TomlValue v → String {
    : String out ( string_with_cap 24 )
    ?? v {
        TStr s → ( string_push_str out ( string_data s ) )
        TInt n → ( string_push_int out n )
        TFloat x → {
            // Bound, not nested: the rendering is a fresh allocation and a
            // call argument owns nothing (docs/MEMORY.md §1). The binding
            // carries the drop.
            : s fs ( float_to_string x )
            ( string_push_str out fs )
        }
        TBool b → ( string_push_str out ? b `true` `false` )
        TArr arr → {
            : i n ( vec_len [TomlValue] arr )
            : ~ i k 0
            ~ < k n {
                ? > k 0 { ( string_push_str out ` ` ) } {}
                ?? ( vec_get [TomlValue] arr k ) {
                    T ev → {
                        : String part ( __mmdt_scalar ev )
                        ( string_push_str out ( string_data part ) )
                        ( string_free part )
                    }
                    F _ → {}
                }
                = k + k 1
            }
        }
        TTable _ → {}
    }
    ^ out
}

@ __mmdt_flatten MmdTheme t s prefix TomlValue v → v {
    ?? v {
        TTable tbl → {
            : i n ( vec_len [TomlEntry] tbl )
            : ~ i i 0
            ~ < i n {
                ?? ( vec_get [TomlEntry] tbl i ) {
                    T ent → {
                        : String key ( __mmdt_join prefix ( string_data . ent key ) )
                        ( __mmdt_flatten t ( string_data key ) . ent value )
                        ( string_free key )
                    }
                    F _ → {}
                }
                = i + i 1
            }
        }
        TFloat _ → {
            : String sv ( __mmdt_scalar v )
            ( mmd_theme_set t prefix ( string_data sv ) )
            ( string_free sv )
        }
        TStr _ → {
            : String sv ( __mmdt_scalar v )
            ( mmd_theme_set t prefix ( string_data sv ) )
            ( string_free sv )
        }
        TInt _ → {
            : String sv ( __mmdt_scalar v )
            ( mmd_theme_set t prefix ( string_data sv ) )
            ( string_free sv )
        }
        TBool _ → {
            : String sv ( __mmdt_scalar v )
            ( mmd_theme_set t prefix ( string_data sv ) )
            ( string_free sv )
        }
        TArr _ → {
            : String sv ( __mmdt_scalar v )
            ( mmd_theme_set t prefix ( string_data sv ) )
            ( string_free sv )
        }
    }
}

: MmdThemeRes {
    b ok
    MmdTheme theme
    String message
}

// Parse one template's TOML text. `name` is the fallback display name
// (the file stem) when the file omits `name = "..."`.
@ mmd_theme_parse s name s src → MmdThemeRes {
    : MmdTheme t ( mmd_theme_new name )
    ?? ( toml_parse src ) {
        T root → {
            ( __mmdt_flatten t `` root )
            ( toml_value_free root )
            : s nm ( mmd_theme_str t `name` `` )
            ? > ( nurl_str_len nm ) 0 {
                ( string_clear . t name )
                ( string_push_str . t name nm )
            } {}
            ( string_push_str . t desc ( mmd_theme_str t `description` `` ) )
            ^ @ MmdThemeRes { T t ( string_new ) }
        }
        F e → {
            : String m ( string_with_cap 64 )
            ( string_push_str m `invalid TOML (` )
            ( string_push_str m ( toml_err_name e ) )
            ( string_push_str m `)` )
            ^ @ MmdThemeRes { F t m }
        }
    }
}

// ── Template sets ────────────────────────────────────────────────────

: MmdTemplate {
    String name
    String path
    MmdTheme theme
}

: MmdTemplateSet {
    i kind
    String root
    ( Vec MmdTemplate ) items
    String default_name
}

@ mmd_templates_free MmdTemplateSet ts → v {
    ( string_free . ts root )
    ( string_free . ts default_name )
    : i n ( vec_len [MmdTemplate] . ts items )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [MmdTemplate] . ts items i ) {
            T tp → {
                ( string_free . tp name )
                ( string_free . tp path )
                ( mmd_theme_free . tp theme )
            }
            F _ → {}
        }
        = i + i 1
    }
    ( vec_free [MmdTemplate] . ts items )
}

@ mmd_templates_count MmdTemplateSet ts → i { ^ ( vec_len [MmdTemplate] . ts items ) }

// Index of the template with this name, or -1. An empty name means "the
// default one".
@ mmd_templates_find MmdTemplateSet ts s name → i {
    ? == ( nurl_str_len name ) 0 {
        ^ ( mmd_templates_find ts ( string_data . ts default_name ) )
    } {}
    : i n ( vec_len [MmdTemplate] . ts items )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [MmdTemplate] . ts items i ) {
            T tp → {
                ? != 0 ( nurl_str_eq ( string_data . tp name ) name ) { ^ i } {}
            }
            F _ → {}
        }
        = i + i 1
    }
    ^ - 0 1
}

@ mmd_templates_theme MmdTemplateSet ts i idx → MmdTheme {
    ?? ( vec_get [MmdTemplate] . ts items idx ) {
        T tp → ^ . tp theme
        F _ → {}
    }
    ^ ( mmd_theme_new `` )  // unreachable for a checked index
}

@ __mmdt_is_toml String name → b {
    ^ ( string_ends_with name `.toml` )
}

// `dir_list` order is platform-defined; templates are listed and picked by
// name, so sort the file names to make the listing and the "first file
// wins" default deterministic.
@ __mmdt_sort_names ( Vec String ) v → v {
    : i n ( vec_len [String] v )
    : ~ i i 1
    ~ < i n {
        ?? ( vec_get [String] v i ) {
            T cur → {
                : ~ i j - i 1
                : ~ b placed F
                ~ & ! placed >= j 0 {
                    ?? ( vec_get [String] v j ) {
                        T prev → {
                            ? > ( nurl_str_cmp ( string_data prev ) ( string_data cur ) ) 0 {
                                ( vec_set [String] v + j 1 prev )
                                = j - j 1
                            } { = placed T }
                        }
                        F _ → { = placed T }
                    }
                }
                ( vec_set [String] v + j 1 cur )
            }
            F _ → {}
        }
        = i + i 1
    }
}

: MmdTemplatesRes {
    b ok
    MmdTemplateSet set
    String message
}

@ __mmdt_empty_set i kind s root → MmdTemplateSet {
    ^ @ MmdTemplateSet {
        kind
        ( string_from root )
        ( vec_new [MmdTemplate] )
        ( string_new )
    }
}

// Load every `*.toml` in `root` as a template. The default template is the
// one whose file sets `default = true`, else the one named `default`, else
// the first by file name.
@ __mmdt_load_dir s root → MmdTemplatesRes {
    : MmdTemplateSet ts ( __mmdt_empty_set MMD_TSRC_DIR root )
    ?? ( dir_list root ) {
        T names → {
            ( __mmdt_sort_names names )
            : i n ( vec_len [String] names )
            : ~ i i 0
            : ~ i explicit - 0 1
            ~ < i n {
                ?? ( vec_get [String] names i ) {
                    T fname → {
                        ? ( __mmdt_is_toml fname ) {
                            : String full ( path_join root ( string_data fname ) )
                            : String stem ( string_substr fname 0 - ( string_len fname ) 5 )
                            ?? ( read_file ( string_data full ) ) {
                                T src → {
                                    : MmdThemeRes tr ( mmd_theme_parse ( string_data stem ) ( string_data src ) )
                                    ( string_free src )
                                    : MmdTheme th . tr theme
                                    ? . tr ok {
                                        : MmdTemplate tp @ MmdTemplate {
                                            ( string_clone . th name )
                                            ( string_clone full )
                                            th
                                        }
                                        ? != 0 ( nurl_str_eq ( mmd_theme_str th `default` `` ) `true` ) {
                                            = explicit ( vec_len [MmdTemplate] . ts items )
                                        } {}
                                        ( vec_push [MmdTemplate] . ts items tp )
                                        ( string_free . tr message )
                                    } {
                                        ( mmd_theme_free th )
                                        : String m ( string_with_cap 96 )
                                        ( string_push_str m ( string_data full ) )
                                        ( string_push_str m `: ` )
                                        ( string_push_str m ( string_data . tr message ) )
                                        ( string_free . tr message )
                                        ( string_free full )
                                        ( string_free stem )
                                        ( string_free fname )
                                        ( __mmdt_free_names names i n )
                                        ( mmd_templates_free ts )
                                        ^ @ MmdTemplatesRes { F ( __mmdt_empty_set MMD_TSRC_DIR root ) m }
                                    }
                                }
                                F _ → {}
                            }
                            ( string_free full )
                            ( string_free stem )
                        } {}
                        ( string_free fname )
                    }
                    F _ → {}
                }
                = i + i 1
            }
            ( vec_free [String] names )

            ? == ( vec_len [MmdTemplate] . ts items ) 0 {
                : String m ( string_with_cap 128 )
                ( string_push_str m `no *.toml templates in ` )
                ( string_push_str m root )
                ( mmd_templates_free ts )
                ^ @ MmdTemplatesRes { F ( __mmdt_empty_set MMD_TSRC_DIR root ) m }
            } {}

            : ~ i pick ? >= explicit 0 explicit 0
            ? < explicit 0 {
                : i named ( mmd_templates_find ts `default` )
                ? >= named 0 { = pick named } {}
            } {}
            ?? ( vec_get [MmdTemplate] . ts items pick ) {
                T tp → ( string_push_str . ts default_name ( string_data . tp name ) )
                F _ → {}
            }
            ^ @ MmdTemplatesRes { T ts ( string_new ) }
        }
        F e → {
            : String m ( string_with_cap 128 )
            ( string_push_str m `cannot read template directory ` )
            ( string_push_str m root )
            ( string_push_str m ` (` )
            ( string_push_str m ( io_err_msg e ) )
            ( string_push_str m `)` )
            ( mmd_templates_free ts )
            ^ @ MmdTemplatesRes { F ( __mmdt_empty_set MMD_TSRC_DIR root ) m }
        }
    }
}

// Free the tail of a name vector abandoned on an error path.
@ __mmdt_free_names ( Vec String ) names i from i n → v {
    : ~ i k + from 1
    ~ < k n {
        ?? ( vec_get [String] names k ) {
            T s → ( string_free s )
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free [String] names )
}

// The one entry point a caller needs: load a template set from `root`
// using source `kind`.
@ mmd_templates_load i kind s root → MmdTemplatesRes {
    ? == kind MMD_TSRC_DIR { ^ ( __mmdt_load_dir root ) } {}
    : String m ( string_with_cap 48 )
    ( string_push_str m `unknown template source kind ` )
    ( string_push_int m kind )
    ^ @ MmdTemplatesRes { F ( __mmdt_empty_set kind root ) m }
}

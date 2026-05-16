// stdlib/ext/toml.nu — minimal TOML parser for NURL manifests and lockfiles.
//
// Scope: enough TOML to round-trip a `nurl.toml` manifest and a
// `nurl.lock` lockfile shaped like Cargo's. Excludes parts of the
// 1.0 spec not used by the package manager:
//
//   * Float, datetime, multi-line / literal strings.
//   * Hex / octal / binary integer literals.
//   * Dotted keys outside `[section]` headers (no `a.b = 1` at scope).
//
// Included:
//
//   * Bare keys `[a-zA-Z0-9_-]+` and quoted `"..."` keys.
//   * String values with `\\`, `\"`, `\n`, `\t`, `\r` escapes.
//   * Signed decimal integers.
//   * Booleans `true` / `false`.
//   * Arrays `[a, b, c]` (homogeneous + inline-table elements).
//   * Inline tables `{ k = v, k2 = v2 }`.
//   * Section headers `[a.b.c]` (dotted path → nested tables).
//   * Array-of-tables `[[name]]` (used by `nurl.lock`'s `[[package]]`).
//   * `#` comments to end of line.
//
// AST mirrors JSON's tagged-union shape so callers familiar with
// `stdlib/ext/json.nu` find the API instantly recognisable.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

: TomlEntry {
    String key
    TomlValue value
}

: | TomlValue {
    TStr String
    TInt i
    TBool b
    TArr ( Vec TomlValue )
    TTable ( Vec TomlEntry )
}

: | TomlErr {
    TomlSyntax
    TomlUnterminated
    TomlBadEscape
    TomlOther
}

@ toml_err_name TomlErr e → s {
    ^ ?? e {
        TomlSyntax → `TomlSyntax`
        TomlUnterminated → `TomlUnterminated`
        TomlBadEscape → `TomlBadEscape`
        TomlOther → `TomlOther`
    }
}

// ── Memory (cascading free) ──────────────────────────────────────

@ toml_value_free TomlValue v → v {
    ?? v {
        TStr s → ( string_free s )
        TInt _ → {}
        TBool _ → {}
        TArr arr → {
            : i n ( vec_len [TomlValue] arr )
            : ~ i k 0
            ~ < k n {
                : ?TomlValue ek ( vec_get [TomlValue] arr k )
                ?? ek {
                    T ev → ( toml_value_free ev )
                    F _ → {}
                }
                = k + k 1
            }
            ( vec_free [TomlValue] arr )
        }
        TTable tbl → {
            : i n ( vec_len [TomlEntry] tbl )
            : ~ i k 0
            ~ < k n {
                : ?TomlEntry ek ( vec_get [TomlEntry] tbl k )
                ?? ek {
                    T ev → {
                        ( string_free . ev key )
                        ( toml_value_free . ev value )
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ( vec_free [TomlEntry] tbl )
        }
    }
}

// ── Char-class predicates ────────────────────────────────────────

@ __t_is_ws i c → b {
    // `|` is strictly binary (docs/GOTCHAS.md item 1) — pair via
    // intermediate bindings instead of nesting parens (which would
    // be parsed as `( fn args )` calls).
    : b a | == c 32 == c 9
    : b b1 | == c 13 == c 11
    ^ | a b1
}

@ __t_is_alpha i c → b {
    | & >= c 65 <= c 90 & >= c 97 <= c 122
}

@ __t_is_digit i c → b {
    & >= c 48 <= c 57
}

@ __t_is_bare i c → b {
    ? ( __t_is_alpha c ) { ^ T } {}
    ? ( __t_is_digit c ) { ^ T } {}
    ? == c 95 { ^ T } {}
    ? == c 45 { ^ T } {}
    ^ F
}

@ __t_get s src i p i n → i {
    ? >= p n { ^ - 0 1 } {}
    ^ ( nurl_str_get src p )
}

// ── Whitespace + comment skipping ────────────────────────────────
//
// `__t_skip_inline` stops at newlines so the table-scope parser can
// see them as record separators. `__t_skip_all` consumes newlines.
// Both also eat `#`-prefixed line comments.

@ __t_skip_inline s src i n i pos → i {
    : ~ i p pos
    : ~ b going T
    ~ going {
        : i c ( __t_get src p n )
        ? ( __t_is_ws c ) { = p + p 1 } {
            ? == c 35 {
                ~ & < p n != ( nurl_str_get src p ) 10 {
                    = p + p 1
                }
            } { = going F }
        }
    }
    ^ p
}

@ __t_skip_all s src i n i pos → i {
    : ~ i p pos
    : ~ b going T
    ~ going {
        : i c ( __t_get src p n )
        ? | ( __t_is_ws c ) == c 10 { = p + p 1 } {
            ? == c 35 {
                ~ & < p n != ( nurl_str_get src p ) 10 {
                    = p + p 1
                }
            } { = going F }
        }
    }
    ^ p
}

// ── Result shapes ────────────────────────────────────────────────
//
// Parser primitives return small typed records that pair the parsed
// value with the new cursor position. We avoid out-params by always
// flowing the new `pos` back through the struct.

: KeyResult {
    b ok
    TomlErr err
    String key
    i pos
}

: ValueResult {
    b ok
    TomlErr err
    TomlValue value
    i pos
}

@ __keyresult_ok String key i pos → KeyResult {
    ^ @ KeyResult { T # TomlErr TomlOther key pos }
}

@ __keyresult_err TomlErr e i pos → KeyResult {
    ^ @ KeyResult { F e ( string_new ) pos }
}

@ __valresult_ok TomlValue v i pos → ValueResult {
    ^ @ ValueResult { T # TomlErr TomlOther v pos }
}

@ __valresult_err TomlErr e i pos → ValueResult {
    ^ @ ValueResult { F e # TomlValue TBool pos }
}

// ── Bare / quoted key parser ─────────────────────────────────────

@ __t_parse_key s src i n i pos → KeyResult {
    : i p pos
    ? >= p n { ^ ( __keyresult_err # TomlErr TomlSyntax p ) } {}
    : i c ( nurl_str_get src p )
    ? == c 34 {
        // Quoted key.
        ^ ( __t_parse_quoted_string src n p )
    } {}
    ? ! ( __t_is_bare c ) {
        ^ ( __keyresult_err # TomlErr TomlSyntax p )
    } {}
    : ~ i k p
    ~ & < k n ( __t_is_bare ( nurl_str_get src k ) ) {
        = k + k 1
    }
    : String key ( string_with_cap - k p )
    : ~ i j p
    ~ < j k {
        ( string_push_char key ( nurl_str_get src j ) )
        = j + j 1
    }
    ^ ( __keyresult_ok key k )
}

// Parse a `"..."`-delimited string, returning the unescaped content.
// Cursor must be on the opening `"`.
@ __t_parse_quoted_string s src i n i pos → KeyResult {
    : i p + pos 1
    : String out ( string_with_cap 32 )
    : ~ b done F
    : ~ b err F
    : ~ TomlErr ek # TomlErr TomlSyntax
    : ~ i cur p
    ~ ! done {
        ? >= cur n {
            = err T  = ek # TomlErr TomlUnterminated  = done T
        } {
            : i c ( nurl_str_get src cur )
            ? == c 34 {
                = cur + cur 1
                = done T
            } {
                ? == c 92 {
                    ? >= + cur 1 n {
                        = err T  = ek # TomlErr TomlUnterminated  = done T
                    } {
                        : i nc ( nurl_str_get src + cur 1 )
                        ? == nc 110 { ( string_push_char out 10 )  = cur + cur 2 } {
                            ? == nc 116 { ( string_push_char out 9 )  = cur + cur 2 } {
                                ? == nc 114 { ( string_push_char out 13 )  = cur + cur 2 } {
                                    ? == nc 92 { ( string_push_char out 92 )  = cur + cur 2 } {
                                        ? == nc 34 { ( string_push_char out 34 )  = cur + cur 2 } {
                                            = err T  = ek # TomlErr TomlBadEscape  = done T
                                        }
                                    }
                                }
                            }
                        }
                    }
                } {
                    ( string_push_char out c )
                    = cur + cur 1
                }
            }
        }
    }
    ? err {
        ( string_free out )
        ^ ( __keyresult_err ek cur )
    } {}
    ^ ( __keyresult_ok out cur )
}

// ── Value parser ─────────────────────────────────────────────────

@ __t_parse_value s src i n i pos → ValueResult {
    : i p ( __t_skip_inline src n pos )
    ? >= p n {
        ^ ( __valresult_err # TomlErr TomlSyntax p )
    } {}
    : i c ( nurl_str_get src p )
    // String.
    ? == c 34 {
        : KeyResult kr ( __t_parse_quoted_string src n p )
        ? . kr ok {
            ^ ( __valresult_ok @ TomlValue { TStr . kr key } . kr pos )
        } {
            ( string_free . kr key )
            ^ ( __valresult_err . kr err . kr pos )
        }
    } {}
    // Boolean.
    ? ( __t_is_alpha c ) {
        : i tlen ? <= + p 4 n 4 - n p
        ? & == tlen 4
            & == ( nurl_str_get src p ) 116
            & == ( nurl_str_get src + p 1 ) 114
            & == ( nurl_str_get src + p 2 ) 117
              == ( nurl_str_get src + p 3 ) 101 {
            ^ ( __valresult_ok @ TomlValue { TBool T } + p 4 )
        } {}
        ? & >= - n p 5
            & == ( nurl_str_get src p ) 102
            & == ( nurl_str_get src + p 1 ) 97
            & == ( nurl_str_get src + p 2 ) 108
            & == ( nurl_str_get src + p 3 ) 115
              == ( nurl_str_get src + p 4 ) 101 {
            ^ ( __valresult_ok @ TomlValue { TBool F } + p 5 )
        } {}
        ^ ( __valresult_err # TomlErr TomlSyntax p )
    } {}
    // Integer (signed decimal).
    ? | == c 45 ( __t_is_digit c ) {
        : ~ i k p
        ? == c 45 { = k + k 1 } {}
        ? ! ( __t_is_digit ( __t_get src k n ) ) {
            ^ ( __valresult_err # TomlErr TomlSyntax p )
        } {}
        ~ & < k n ( __t_is_digit ( nurl_str_get src k ) ) {
            = k + k 1
        }
        : String num_s ( string_with_cap - k p )
        : ~ i j p
        ~ < j k {
            ( string_push_char num_s ( nurl_str_get src j ) )
            = j + j 1
        }
        : !i ParseErr nr ( string_to_int num_s )
        ( string_free num_s )
        ?? nr {
            T iv → ^ ( __valresult_ok @ TomlValue { TInt iv } k )
            F _ → ^ ( __valresult_err # TomlErr TomlSyntax p )
        }
    } {}
    // Array.
    ? == c 91 {
        ^ ( __t_parse_array src n p )
    } {}
    // Inline table.
    ? == c 123 {
        ^ ( __t_parse_inline_table src n p )
    } {}
    ^ ( __valresult_err # TomlErr TomlSyntax p )
}

@ __t_parse_array s src i n i pos → ValueResult {
    : i p + pos 1
    : ( Vec TomlValue ) items ( vec_new [TomlValue] )
    : ~ b done F
    : ~ b err F
    : ~ TomlErr ek # TomlErr TomlSyntax
    : ~ i cur p
    ~ ! done {
        = cur ( __t_skip_all src n cur )
        ? >= cur n {
            = err T  = ek # TomlErr TomlUnterminated  = done T
        } {
            : i c ( nurl_str_get src cur )
            ? == c 93 {
                = cur + cur 1
                = done T
            } {
                : ValueResult vr ( __t_parse_value src n cur )
                ? . vr ok {
                    ( vec_push [TomlValue] items . vr value )
                    = cur ( __t_skip_all src n . vr pos )
                    : i nc ( __t_get src cur n )
                    ? == nc 44 { = cur + cur 1 } {
                        ? != nc 93 {
                            = err T  = ek . vr err  = done T
                        } {}
                    }
                } { = err T  = ek . vr err  = done T }
            }
        }
    }
    ? err {
        : i nfree ( vec_len [TomlValue] items )
        : ~ i fk 0
        ~ < fk nfree {
            : ?TomlValue iv ( vec_get [TomlValue] items fk )
            ?? iv {
                T v → ( toml_value_free v )
                F _ → {}
            }
            = fk + fk 1
        }
        ( vec_free [TomlValue] items )
        ^ ( __valresult_err ek cur )
    } {}
    ^ ( __valresult_ok @ TomlValue { TArr items } cur )
}

@ __t_parse_inline_table s src i n i pos → ValueResult {
    : i p + pos 1
    : ( Vec TomlEntry ) entries ( vec_new [TomlEntry] )
    : ~ b done F
    : ~ b err F
    : ~ TomlErr ek # TomlErr TomlSyntax
    : ~ i cur p
    ~ ! done {
        = cur ( __t_skip_inline src n cur )
        : i c ( __t_get src cur n )
        ? == c 125 {
            = cur + cur 1
            = done T
        } {
            : KeyResult kr ( __t_parse_key src n cur )
            ? . kr ok {
                = cur ( __t_skip_inline src n . kr pos )
                ? != ( __t_get src cur n ) 61 {
                    ( string_free . kr key )
                    = err T  = done T
                } {
                    = cur + cur 1
                    : ValueResult vr ( __t_parse_value src n cur )
                    ? . vr ok {
                        ( vec_push [TomlEntry] entries @ TomlEntry { . kr key . vr value } )
                        = cur ( __t_skip_inline src n . vr pos )
                        : i nc ( __t_get src cur n )
                        ? == nc 44 { = cur + cur 1 } {
                            ? != nc 125 {
                                = err T  = done T
                            } {}
                        }
                    } {
                        ( string_free . kr key )
                        = err T  = ek . vr err  = done T
                    }
                }
            } { = err T  = ek . kr err  = done T }
        }
    }
    ? err {
        : i nfree ( vec_len [TomlEntry] entries )
        : ~ i fk 0
        ~ < fk nfree {
            : ?TomlEntry ek0 ( vec_get [TomlEntry] entries fk )
            ?? ek0 {
                T e → {
                    ( string_free . e key )
                    ( toml_value_free . e value )
                }
                F _ → {}
            }
            = fk + fk 1
        }
        ( vec_free [TomlEntry] entries )
        ^ ( __valresult_err ek cur )
    } {}
    ^ ( __valresult_ok @ TomlValue { TTable entries } cur )
}

// ── Section helper: walk dotted path, inserting tables as needed.
//
// `target` is the current top-level TTable's Vec[TomlEntry]. `path` is
// a Vec[String] of header components. Returns the Vec[TomlEntry] of
// the leaf table — caller appends KV pairs onto that. For
// `[[name]]` array-of-tables (`as_array = T`), the leaf path
// component becomes a TArr whose elements are TTable; this fn appends
// a fresh TTable and returns its entry vec.

@ __t_descend ( Vec TomlEntry ) target ( Vec String ) path b as_array → ( Vec TomlEntry ) {
    : i depth ( vec_len [String] path )
    : ~ ( Vec TomlEntry ) cur target
    : ~ i d 0
    ~ < d depth {
        : ?String key_o ( vec_get [String] path d )
        : ~ ( Vec TomlEntry ) next_tbl cur
        ?? key_o {
            T key → {
                : i cn ( vec_len [TomlEntry] cur )
                : ~ i found - 0 1
                : ~ i k 0
                ~ & < found 0 < k cn {
                    : ?TomlEntry ek ( vec_get [TomlEntry] cur k )
                    ?? ek {
                        T ev → {
                            ? ( nurl_str_eq ( string_data . ev key ) ( string_data key ) ) {
                                = found k
                            } {}
                        }
                        F _ → {}
                    }
                    = k + k 1
                }
                ? & == d - depth 1 as_array {
                    // Leaf level for [[name]] — append a fresh TTable to
                    // the array. Reuse / create the array.
                    : ( Vec TomlEntry ) inner ( vec_new [TomlEntry] )
                    ? >= found 0 {
                        : ?TomlEntry old_o ( vec_get [TomlEntry] cur found )
                        ?? old_o {
                            T old → {
                                ?? . old value {
                                    TArr arr → ( vec_push [TomlValue] arr @ TomlValue { TTable inner } )
                                    _ → {}
                                }
                            }
                            F _ → {}
                        }
                    } {
                        : ( Vec TomlValue ) arr ( vec_new [TomlValue] )
                        ( vec_push [TomlValue] arr @ TomlValue { TTable inner } )
                        ( vec_push [TomlEntry] cur @ TomlEntry { ( string_from ( string_data key ) ) @ TomlValue { TArr arr } } )
                    }
                    = next_tbl inner
                } {
                    // Plain descent — find or create TTable child.
                    ? >= found 0 {
                        : ?TomlEntry old_o ( vec_get [TomlEntry] cur found )
                        ?? old_o {
                            T old → {
                                ?? . old value {
                                    TTable t → = next_tbl t
                                    _ → {}
                                }
                            }
                            F _ → {}
                        }
                    } {
                        : ( Vec TomlEntry ) child ( vec_new [TomlEntry] )
                        ( vec_push [TomlEntry] cur @ TomlEntry { ( string_from ( string_data key ) ) @ TomlValue { TTable child } } )
                        = next_tbl child
                    }
                }
            }
            F _ → {}
        }
        = cur next_tbl
        = d + d 1
    }
    ^ cur
}

// ── Section header parser ────────────────────────────────────────
//
// Reads `[a.b.c]` (single) or `[[a.b.c]]` (array-of-tables). Returns
// the dotted-key Vec[String] (OWNED) + array flag + new position via
// a small helper struct.

: HeaderResult {
    b ok
    b as_array
    ( Vec String ) path
    i pos
}

@ __t_parse_header s src i n i pos → HeaderResult {
    : ( Vec String ) path ( vec_new [String] )
    : i p + pos 1
    : ~ b as_array F
    ? & < p n == ( nurl_str_get src p ) 91 {
        = p + p 1
        = as_array T
    } {}
    : ~ b done F
    : ~ b err F
    : ~ i cur p
    ~ ! done {
        = cur ( __t_skip_inline src n cur )
        : KeyResult kr ( __t_parse_key src n cur )
        ? . kr ok {
            ( vec_push [String] path . kr key )
            = cur ( __t_skip_inline src n . kr pos )
            : i c ( __t_get src cur n )
            ? == c 46 { = cur + cur 1 } {
                ? == c 93 {
                    = cur + cur 1
                    ? as_array {
                        ? != ( __t_get src cur n ) 93 { = err T } {
                            = cur + cur 1
                        }
                    } {}
                    = done T
                } { = err T  = done T }
            }
        } {
            ( string_free . kr key )
            = err T  = done T
        }
    }
    ? err {
        : i nfree ( vec_len [String] path )
        : ~ i fk 0
        ~ < fk nfree {
            : ?String sk ( vec_get [String] path fk )
            ?? sk {
                T sv → ( string_free sv )
                F _ → {}
            }
            = fk + fk 1
        }
        ( vec_free [String] path )
        ^ @ HeaderResult { F as_array ( vec_new [String] ) cur }
    } {}
    ^ @ HeaderResult { T as_array path cur }
}

// ── Top-level driver ─────────────────────────────────────────────

@ toml_parse s src → ! TomlValue TomlErr {
    : i n ( nurl_str_len src )
    : ~ ( Vec TomlEntry ) root ( vec_new [TomlEntry] )
    : ~ ( Vec TomlEntry ) current root
    : ~ i pos 0
    : ~ b err F
    : ~ TomlErr ek # TomlErr TomlOther

    ~ & < pos n ! err {
        = pos ( __t_skip_all src n pos )
        ? >= pos n {} {
            : i c ( nurl_str_get src pos )
            ? == c 91 {
                : HeaderResult hr ( __t_parse_header src n pos )
                ? . hr ok {
                    = current ( __t_descend root . hr path . hr as_array )
                    : i pn ( vec_len [String] . hr path )
                    : ~ i fk 0
                    ~ < fk pn {
                        : ?String sk ( vec_get [String] . hr path fk )
                        ?? sk {
                            T sv → ( string_free sv )
                            F _ → {}
                        }
                        = fk + fk 1
                    }
                    ( vec_free [String] . hr path )
                    = pos . hr pos
                } { = err T  = ek # TomlErr TomlSyntax  = pos . hr pos }
            } {
                : KeyResult kr ( __t_parse_key src n pos )
                ? . kr ok {
                    : i ap ( __t_skip_inline src n . kr pos )
                    ? != ( __t_get src ap n ) 61 {
                        ( string_free . kr key )
                        = err T  = ek # TomlErr TomlSyntax  = pos ap
                    } {
                        : ValueResult vr ( __t_parse_value src n + ap 1 )
                        ? . vr ok {
                            ( vec_push [TomlEntry] current @ TomlEntry { . kr key . vr value } )
                            = pos . vr pos
                        } {
                            ( string_free . kr key )
                            = err T  = ek . vr err  = pos . vr pos
                        }
                    }
                } { = err T  = ek . kr err  = pos . kr pos }
            }
        }
    }
    ? err {
        ( toml_value_free @ TomlValue { TTable root } )
        ^ @ ! TomlValue TomlErr { F ek }
    } {}
    ^ @ ! TomlValue TomlErr { T @ TomlValue { TTable root } }
}

// ── Query helpers ────────────────────────────────────────────────

@ toml_get TomlValue v s key → ? TomlValue {
    ?? v {
        TTable entries → {
            : i n ( vec_len [TomlEntry] entries )
            : ~ i k 0
            ~ < k n {
                : ?TomlEntry ek ( vec_get [TomlEntry] entries k )
                ?? ek {
                    T ev → {
                        ? ( nurl_str_eq ( string_data . ev key ) key ) {
                            ^ @ ? TomlValue { T . ev value }
                        } {}
                    }
                    F _ → {}
                }
                = k + k 1
            }
        }
        _ → {}
    }
    ^ @ ? TomlValue { F # TomlValue TBool }
}

// Walk a dotted path like "package.name". Returns the leaf value or
// None at the first missing segment.
@ toml_get_path TomlValue v s path → ? TomlValue {
    : i n ( nurl_str_len path )
    : ~ i start 0
    : ~ TomlValue cur v
    : ~ b ok T
    ~ & ok < start n {
        : ~ i end start
        ~ & < end n != ( nurl_str_get path end ) 46 {
            = end + end 1
        }
        : String seg ( string_with_cap - end start )
        : ~ i j start
        ~ < j end {
            ( string_push_char seg ( nurl_str_get path j ) )
            = j + j 1
        }
        : ? TomlValue nx ( toml_get cur ( string_data seg ) )
        ( string_free seg )
        ?? nx {
            T v2 → = cur v2
            F _ → = ok F
        }
        = start ? < end n + end 1 end
    }
    ? ok { ^ @ ? TomlValue { T cur } } {}
    ^ @ ? TomlValue { F # TomlValue TBool }
}

@ toml_as_str TomlValue v → ? String {
    ?? v {
        TStr s → ^ @ ? String { T ( string_from ( string_data s ) ) }
        _ → {}
    }
    ^ @ ? String { F ( string_new ) }
}

@ toml_as_int TomlValue v → ? i {
    ?? v {
        TInt n → ^ @ ? i { T n }
        _ → {}
    }
    ^ @ ? i { F 0 }
}

@ toml_as_bool TomlValue v → ? b {
    ?? v {
        TBool x → ^ @ ? b { T x }
        _ → {}
    }
    ^ @ ? b { F F }
}

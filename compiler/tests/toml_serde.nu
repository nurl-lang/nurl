// toml_serde.nu — exercises the TOML side of stdlib/serde.nu and the
// toml_stringify serializer added to stdlib/ext/toml.nu.
//
//   * to_toml builtin impls (i / b / s) — checked by stringifying.
//   * from_toml_i / _b / _string decoders, including a type mismatch.
//   * toml_stringify of a table.
//   * a full round-trip: build a TomlValue → toml_stringify →
//     toml_parse → read the values back.
//   * a user struct with its own % TomlSerialize impl.
//
// Expected output:
//   enc int: ok
//   enc bool: ok
//   enc str: ok
//   dec int: ok
//   dec bool: ok
//   dec str: ok
//   dec mismatch: ok
//   stringify table: ok
//   rt name: ok
//   rt n: ok
//   rt ok: ok
//   struct port: ok
//   struct tls: ok

$ `stdlib/serde.nu`
$ `stdlib/ext/toml.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/errors.nu`

@ say s label b cond → v {
    ? cond {
        ( nurl_print label ) ( nurl_print `: ok\n` )
    } {
        ( nurl_print label ) ( nurl_print `: FAIL\n` )
    }
}

// stringify `v` (consumed), compare the text to `want`.
@ ck_enc s label TomlValue v s want → v {
    : String txt ( toml_stringify v )
    ( say label != 0 ( nurl_str_eq ( string_data txt ) want ) )
    ( string_free txt )
    ( toml_value_free v )
}

: Server { i port b tls }

% TomlSerialize Server {
    @ to_toml Server sv → TomlValue {
        : ( Vec TomlEntry ) e ( vec_new [TomlEntry] )
        ( vec_push [TomlEntry] e @ TomlEntry { ( string_from `port` ) ( to_toml . sv port ) } )
        ( vec_push [TomlEntry] e @ TomlEntry { ( string_from `tls` ) ( to_toml . sv tls ) } )
        ^ @ TomlValue { TTable e }
    }
}

@ main → i {
    // ── to_toml builtins (verified through toml_stringify) ──────────
    ( ck_enc `enc int` ( to_toml 42 ) `42` )
    ( ck_enc `enc bool` ( to_toml T ) `true` )
    ( ck_enc `enc str` ( to_toml `hi` ) `"hi"` )

    // ── from_toml_* decoders ────────────────────────────────────────
    : TomlValue iv ( to_toml 99 )
    ?? ( from_toml_i iv ) {
        T n → ( say `dec int` == n 99 )
        F e → ( say `dec int` F )
    }
    ( toml_value_free iv )

    : TomlValue bv ( to_toml F )
    ?? ( from_toml_b bv ) {
        T x → ( say `dec bool` == x F )
        F e → ( say `dec bool` F )
    }
    ( toml_value_free bv )

    : TomlValue sv ( to_toml `xyz` )
    ?? ( from_toml_string sv ) {
        T s → {
            ( say `dec str` != 0 ( nurl_str_eq ( string_data s ) `xyz` ) )
            ( string_free s )
        }
        F e → ( say `dec str` F )
    }
    ( toml_value_free sv )

    // from_toml_i on a non-integer must fail.
    : TomlValue mv ( to_toml T )
    ?? ( from_toml_i mv ) {
        T n → ( say `dec mismatch` F )
        F e → ( say `dec mismatch` T )
    }
    ( toml_value_free mv )

    // ── toml_stringify of a table + round-trip through toml_parse ───
    : ( Vec TomlEntry ) e ( vec_new [TomlEntry] )
    ( vec_push [TomlEntry] e @ TomlEntry { ( string_from `name` ) ( to_toml `nurl` ) } )
    ( vec_push [TomlEntry] e @ TomlEntry { ( string_from `n` ) ( to_toml 7 ) } )
    ( vec_push [TomlEntry] e @ TomlEntry { ( string_from `ok` ) ( to_toml T ) } )
    : TomlValue tbl @ TomlValue { TTable e }
    : String txt ( toml_stringify tbl )
    ( say `stringify table` != 0 ( nurl_str_eq ( string_data txt ) `name = "nurl"\nn = 7\nok = true\n` ) )

    ?? ( toml_parse ( string_data txt ) ) {
        T parsed → {
            ?? ( toml_get parsed `name` ) {
                T nv → {
                    ?? ( from_toml_string nv ) {
                        T s → {
                            ( say `rt name` != 0 ( nurl_str_eq ( string_data s ) `nurl` ) )
                            ( string_free s )
                        }
                        F e → ( say `rt name` F )
                    }
                }
                F → ( say `rt name` F )
            }
            ?? ( toml_get parsed `n` ) {
                T nv → {
                    ?? ( from_toml_i nv ) {
                        T x → ( say `rt n` == x 7 )
                        F e → ( say `rt n` F )
                    }
                }
                F → ( say `rt n` F )
            }
            ?? ( toml_get parsed `ok` ) {
                T nv → {
                    ?? ( from_toml_b nv ) {
                        T x → ( say `rt ok` == x T )
                        F e → ( say `rt ok` F )
                    }
                }
                F → ( say `rt ok` F )
            }
            ( toml_value_free parsed )
        }
        F e → {
            ( say `rt name` F )
            ( say `rt n` F )
            ( say `rt ok` F )
        }
    }
    ( string_free txt )
    ( toml_value_free tbl )

    // ── A user struct with its own % TomlSerialize impl ─────────────
    : Server srv @ Server { 8080 T }
    : TomlValue stv ( to_toml srv )
    : String stxt ( toml_stringify stv )
    ?? ( toml_parse ( string_data stxt ) ) {
        T parsed → {
            ?? ( toml_get parsed `port` ) {
                T pv → {
                    ?? ( from_toml_i pv ) {
                        T x → ( say `struct port` == x 8080 )
                        F e → ( say `struct port` F )
                    }
                }
                F → ( say `struct port` F )
            }
            ?? ( toml_get parsed `tls` ) {
                T tv → {
                    ?? ( from_toml_b tv ) {
                        T x → ( say `struct tls` == x T )
                        F e → ( say `struct tls` F )
                    }
                }
                F → ( say `struct tls` F )
            }
            ( toml_value_free parsed )
        }
        F e → {
            ( say `struct port` F )
            ( say `struct tls` F )
        }
    }
    ( string_free stxt )
    ( toml_value_free stv )

    ^ 0
}

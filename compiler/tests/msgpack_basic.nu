// msgpack_basic.nu — exercises stdlib/ext/msgpack.nu.
//
// Three kinds of check, each printing `<label>: ok` / `<label>: FAIL`:
//   rt        — parse JSON → msgpack_encode → msgpack_decode → json_eq
//   enc       — encode a value, compare the bytes (hex) to the spec form
//   dec_int   — decode a hand-written msgpack int, compare the value
//   dec_str   — decode a str8, compare the text
//   dec_err   — a malformed / unsupported input must fail to decode
//
// Encode vectors are checked against https://msgpack.org/ — the smallest
// signed format, big-endian, IEEE-754 float64.
//
// Expected output:
//   rt null: ok
//   rt bool: ok
//   rt int small: ok
//   rt int neg: ok
//   rt int negfix: ok
//   rt int u16: ok
//   rt int i64: ok
//   rt int negbig: ok
//   rt float: ok
//   rt string: ok
//   rt string empty: ok
//   rt array: ok
//   rt object: ok
//   rt nested: ok
//   enc null: ok
//   enc false: ok
//   enc true: ok
//   enc int 0: ok
//   enc int 127: ok
//   enc int -1: ok
//   enc int -32: ok
//   enc int 128: ok
//   enc int 100000: ok
//   enc str a: ok
//   enc str empty: ok
//   enc float 1.5: ok
//   dec uint8: ok
//   dec uint16: ok
//   dec uint32: ok
//   dec int8: ok
//   dec int64: ok
//   dec str8: ok
//   dec err empty: ok
//   dec err bin: ok
//   dec err truncated: ok
//   dec err reserved: ok
//   dec err short array: ok

$ `stdlib/ext/msgpack.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`

// parse JSON → encode → decode → the result must equal the original.
@ rt s label s json_text → v {
    ?? ( json_parse json_text ) {
        T orig → {
            ?? ( msgpack_encode orig ) {
                T bytes → {
                    ?? ( msgpack_decode bytes ) {
                        T back → {
                            ? ( json_eq orig back ) {
                                ( nurl_print label ) ( nurl_print `: ok\n` )
                            } {
                                ( nurl_print label ) ( nurl_print `: FAIL roundtrip\n` )
                            }
                            ( json_free back )
                        }
                        F e → {
                            ( nurl_print label ) ( nurl_print `: FAIL decode ` )
                            ( nurl_print ( msgpack_err_name # MsgpackErr e ) )
                            ( nurl_print `\n` )
                        }
                    }
                    ( vec_free [u] bytes )
                }
                F e → { ( nurl_print label ) ( nurl_print `: FAIL encode\n` ) }
            }
            ( json_free orig )
        }
        F e → { ( nurl_print label ) ( nurl_print `: FAIL parse\n` ) }
    }
}

// encode `j` (consumed), compare the bytes to `want_hex`.
@ enc s label Json j s want_hex → v {
    ?? ( msgpack_encode j ) {
        T bytes → {
            : String h ( bytes_to_hex bytes )
            ? != 0 ( nurl_str_eq ( string_data h ) want_hex ) {
                ( nurl_print label ) ( nurl_print `: ok\n` )
            } {
                ( nurl_print label ) ( nurl_print `: FAIL ` )
                ( nurl_print ( string_data h ) ) ( nurl_print `\n` )
            }
            ( string_free h )
            ( vec_free [u] bytes )
        }
        F e → { ( nurl_print label ) ( nurl_print `: FAIL encode\n` ) }
    }
    ( json_free j )
}

// decode the msgpack hex `in_hex`, expect an integer equal to `want`.
@ dec_int s label s in_hex i want → v {
    ?? ( bytes_from_hex in_hex ) {
        T inb → {
            ?? ( msgpack_decode inb ) {
                T j → {
                    ?? ( json_num_as_i j ) {
                        T n → {
                            ? == n want {
                                ( nurl_print label ) ( nurl_print `: ok\n` )
                            } {
                                ( nurl_print label ) ( nurl_print `: FAIL value\n` )
                            }
                        }
                        F → { ( nurl_print label ) ( nurl_print `: FAIL not int\n` ) }
                    }
                    ( json_free j )
                }
                F e → { ( nurl_print label ) ( nurl_print `: FAIL decode\n` ) }
            }
            ( vec_free [u] inb )
        }
        F e → { ( nurl_print label ) ( nurl_print `: FAIL hex\n` ) }
    }
}

// decode the msgpack hex `in_hex`, expect a string equal to `want`.
@ dec_str s label s in_hex s want → v {
    ?? ( bytes_from_hex in_hex ) {
        T inb → {
            ?? ( msgpack_decode inb ) {
                T j → {
                    ? != 0 ( nurl_str_eq ( json_str_data j ) want ) {
                        ( nurl_print label ) ( nurl_print `: ok\n` )
                    } {
                        ( nurl_print label ) ( nurl_print `: FAIL value\n` )
                    }
                    ( json_free j )
                }
                F e → { ( nurl_print label ) ( nurl_print `: FAIL decode\n` ) }
            }
            ( vec_free [u] inb )
        }
        F e → { ( nurl_print label ) ( nurl_print `: FAIL hex\n` ) }
    }
}

// decode the msgpack hex `in_hex`, expect a decode failure.
@ dec_err s label s in_hex → v {
    ?? ( bytes_from_hex in_hex ) {
        T inb → {
            ?? ( msgpack_decode inb ) {
                T j → {
                    ( nurl_print label ) ( nurl_print `: FAIL unexpected ok\n` )
                    ( json_free j )
                }
                F e → { ( nurl_print label ) ( nurl_print `: ok\n` ) }
            }
            ( vec_free [u] inb )
        }
        F e → { ( nurl_print label ) ( nurl_print `: FAIL hex\n` ) }
    }
}

@ main → i {
    // ── Round-trips ─────────────────────────────────────────────────
    ( rt `rt null` `null` )
    ( rt `rt bool` `true` )
    ( rt `rt int small` `42` )
    ( rt `rt int neg` `-1` )
    ( rt `rt int negfix` `-32` )
    ( rt `rt int u16` `4096` )
    ( rt `rt int i64` `9000000000` )
    ( rt `rt int negbig` `-5000000000` )
    ( rt `rt float` `3.5` )
    ( rt `rt string` `"hello msgpack"` )
    ( rt `rt string empty` `""` )
    ( rt `rt array` `[1,2,3,4,5]` )
    ( rt `rt object` `{"a":1,"b":2}` )
    ( rt `rt nested` `{"name":"x","vals":[1,2,[3,4]],"ok":true,"meta":{"n":null}}` )

    // ── Encode spec vectors ─────────────────────────────────────────
    ( enc `enc null` ( json_null ) `c0` )
    ( enc `enc false` ( json_bool F ) `c2` )
    ( enc `enc true` ( json_bool T ) `c3` )
    ( enc `enc int 0` ( json_int 0 ) `00` )
    ( enc `enc int 127` ( json_int 127 ) `7f` )
    ( enc `enc int -1` ( json_int -1 ) `ff` )
    ( enc `enc int -32` ( json_int -32 ) `e0` )
    ( enc `enc int 128` ( json_int 128 ) `d10080` )
    ( enc `enc int 100000` ( json_int 100000 ) `d2000186a0` )
    ( enc `enc str a` ( json_str_lit `a` ) `a161` )
    ( enc `enc str empty` ( json_str_lit `` ) `a0` )
    ( enc `enc float 1.5` ( json_float 1.5 ) `cb3ff8000000000000` )

    // ── Decode non-canonical formats the encoder never emits ────────
    ( dec_int `dec uint8` `cc80` 128 )
    ( dec_int `dec uint16` `cdffff` 65535 )
    ( dec_int `dec uint32` `ce0001869f` 99999 )
    ( dec_int `dec int8` `d0ff` -1 )
    ( dec_int `dec int64` `d3ffffffffffffffff` -1 )
    ( dec_str `dec str8` `d90568656c6c6f` `hello` )

    // ── Malformed / unsupported inputs ──────────────────────────────
    : ( Vec u ) mp_empty ( vec_new [u] )
    ?? ( msgpack_decode mp_empty ) {
        T j → { ( nurl_print `dec err empty: FAIL unexpected ok\n` ) ( json_free j ) }
        F e → ( nurl_print `dec err empty: ok\n` )
    }
    ( vec_free [u] mp_empty )
    ( dec_err `dec err bin` `c403aabbcc` )
    ( dec_err `dec err truncated` `cd00` )
    ( dec_err `dec err reserved` `c1` )
    ( dec_err `dec err short array` `9201` )

    ^ 0
}

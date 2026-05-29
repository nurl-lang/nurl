// examples/msgpack_demo.nu — round-trip a user struct through
// MessagePack.
//
// MessagePack and JSON share a data model, so a type that already has
// a `% JsonSerialize` impl needs NO MsgPack-specific code: encode by
// composing `to_json` with `msgpack_encode`, decode with
// `msgpack_decode` plus the type's `from_json` helper. Scalars have
// the `from_msgpack_<T>` shortcut. Mirror this shape for your types.
//
// Build:
//   ./nurl.sh examples/msgpack_demo.nu /tmp/msgpack_demo
//   /tmp/msgpack_demo

$ `stdlib/ext/serde.nu`

: Point { i x i y }

// The SAME JsonSerialize impl JSON uses — MsgPack reuses it.
% JsonSerialize Point {
    @ to_json Point p → Json {
        : Json j ( json_obj_new )
        ( json_obj_set j `x` ( to_json . p x ) )
        ( json_obj_set j `y` ( to_json . p y ) )
        ^ j
    }
}

@ point_from_json Json j → !Point ParseErr {
    : ?Json jxo ( json_obj_get j `x` )
    : ?Json jyo ( json_obj_get j `y` )
    ?? jxo {
        T jx → {
            ?? jyo {
                T jy → {
                    : !i ParseErr xr ( from_json_i jx )
                    : !i ParseErr yr ( from_json_i jy )
                    ?? xr {
                        T xv → {
                            ?? yr {
                                T yv → ^ @ !Point ParseErr { T @ Point { xv yv } }
                                F e → ^ @ !Point ParseErr { F e }
                            }
                        }
                        F e → ^ @ !Point ParseErr { F e }
                    }
                }
                F → ^ @ !Point ParseErr { F @ ParseErr { BadFormat } }
            }
        }
        F → ^ @ !Point ParseErr { F @ ParseErr { BadFormat } }
    }
}

@ main → v {
    : Point p @ Point { 3 4 }

    // Encode: trait dispatch routes ( to_json p ) to the Point impl;
    // msgpack_encode turns the Json into MessagePack bytes.
    : Json j ( to_json p )
    // Bind the option to a named variable first — passing a call result
    // directly to `??` with a wide `Vec` payload tickles a known nurlc
    // generic-monomorphize IR bug (see nurl_lang_gotchas memory). The
    // scrutinee binding works around it.
    : !( Vec u ) MsgpackErr _enc_res ( msgpack_encode j )
    ?? _enc_res {
        T bytes → {
            ( nurl_print `encoded:  ` )
            ( nurl_print ( nurl_str_int ( vec_len [u] bytes ) ) )
            ( nurl_print ` bytes\n` )

            // Decode: bytes → Json → Point.
            ?? ( msgpack_decode bytes ) {
                T j2 → {
                    ?? ( point_from_json j2 ) {
                        T p2 → {
                            ( nurl_print `decoded:  Point { ` )
                            ( nurl_print ( nurl_str_int . p2 x ) )
                            ( nurl_print ` ` )
                            ( nurl_print ( nurl_str_int . p2 y ) )
                            ( nurl_print ` }\n` )
                        }
                        F _ → ( nurl_print `decode FAIL\n` )
                    }
                    ( json_free j2 )
                }
                F _ → ( nurl_print `msgpack decode FAIL\n` )
            }
            ( vec_free [u] bytes )
        }
        F _ → ( nurl_print `msgpack encode FAIL\n` )
    }
    ( json_free j )

    // A scalar needs no struct plumbing — from_msgpack_i decodes
    // straight to an i.
    : Json sj ( json_int 1729 )
    : !( Vec u ) MsgpackErr _enc_sj ( msgpack_encode sj )
    ?? _enc_sj {
        T sb → {
            : !i MsgpackErr _dec_sj ( from_msgpack_i sb )
            ?? _dec_sj {
                T n → {
                    ( nurl_print `scalar:   ` )
                    ( nurl_print ( nurl_str_int n ) )
                    ( nurl_print `\n` )
                }
                F _ → ( nurl_print `scalar FAIL\n` )
            }
            ( vec_free [u] sb )
        }
        F _ → ( nurl_print `scalar encode FAIL\n` )
    }
    ( json_free sj )
}

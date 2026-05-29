// examples/serde_demo.nu — round-trip a user struct through JSON via
// the stdlib/ext/serde.nu Serialize trait + a hand-written from_json
// helper. Demonstrates the recommended shape; mirror it for your
// own types.
//
// Build:
//   ./nurl.sh examples/serde_demo.nu /tmp/serde_demo
//   /tmp/serde_demo

$ `stdlib/ext/serde.nu`

// ── A typical leaf struct ──────────────────────────────────────────

: Point { i x i y }

// to_json: build a JObj, set each field via `to_json` recursively.
% JsonSerialize Point {
    @ to_json Point p → Json {
        : Json j ( json_obj_new )
        ( json_obj_set j `x` ( to_json . p x ) )
        ( json_obj_set j `y` ( to_json . p y ) )
        ^ j
    }
}

// from_json: destructure a JObj, decode each field via the matching
// `from_json_<T>` helper, propagate errors via try-propagation.
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

    // Encode side: trait dispatch routes ( to_json p ) to our Point impl.
    : Json j ( to_json p )
    : String s ( json_stringify j )
    ( nurl_print `encoded:  ` ) ( nurl_print ( string_data s ) ) ( nurl_print `\n` )

    // Round-trip: parse the JSON text back, decode into a Point, compare.
    : !Json JsonError pr ( json_parse ( string_data s ) )
    ?? pr {
        T j2 → {
            : !Point ParseErr p2r ( point_from_json j2 )
            ?? p2r {
                T p2 → {
                    ( nurl_print `decoded:  Point { ` )
                    ( nurl_print_int . p2 x )
                    ( nurl_print ` ` )
                    ( nurl_print_int . p2 y )
                    ( nurl_print ` }\n` )
                }
                F _ → ( nurl_print `decode FAIL\n` )
            }
            ( json_free j2 )
        }
        F _ → ( nurl_print `parse FAIL\n` )
    }

    ( string_free s )
    ( json_free j )
}

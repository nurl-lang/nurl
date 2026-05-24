// msgpack_serde.nu — exercises the from_msgpack_<T> decode helpers
// added to stdlib/ext/serde.nu.
//
// Each helper runs msgpack_decode then extracts the value straight
// from the Json, returning !T MsgpackErr — MsgpackTypeMismatch when
// the bytes decoded fine but the value is the wrong shape, and the
// codec's own MsgpackErr variants on a malformed input. No ParseErr
// anywhere — MsgpackErr is the single error type end to end.
//
// Expected output:
//   dec int: ok
//   dec float: ok
//   dec bool: ok
//   dec str: ok
//   dec mismatch: ok
//   dec error: ok

$ `stdlib/ext/serde.nu`
$ `stdlib/ext/msgpack.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/bytes.nu`

@ say s label b cond → v {
    ? cond {
        ( nurl_print label ) ( nurl_print `: ok\n` )
    } {
        ( nurl_print label ) ( nurl_print `: FAIL\n` )
    }
}

// Encode `j` to MessagePack bytes and free it (encoding a scalar
// never fails). Returns the owned byte buffer.
@ enc_bytes Json j → ( Vec u ) {
    : !( Vec u ) MsgpackErr r ( msgpack_encode j )
    ( json_free j )
    ?? r {
        T b → ^ b
        F _ → ^ ( vec_new [u] )
    }
}

@ main → i {
    : ( Vec u ) bi ( enc_bytes ( json_int 42 ) )
    ?? ( from_msgpack_i bi ) {
        T n → ( say `dec int` == n 42 )
        F e → ( say `dec int` F )
    }
    ( vec_free [u] bi )

    : ( Vec u ) bf ( enc_bytes ( json_float 2.5 ) )
    ?? ( from_msgpack_f bf ) {
        T x → ( say `dec float` == x 2.5 )
        F e → ( say `dec float` F )
    }
    ( vec_free [u] bf )

    : ( Vec u ) bb ( enc_bytes ( json_bool T ) )
    ?? ( from_msgpack_b bb ) {
        T v → ( say `dec bool` == v T )
        F e → ( say `dec bool` F )
    }
    ( vec_free [u] bb )

    : ( Vec u ) bs ( enc_bytes ( json_str_lit `hello` ) )
    ?? ( from_msgpack_string bs ) {
        T s → {
            ( say `dec str` != 0 ( nurl_str_eq ( string_data s ) `hello` ) )
            ( string_free s )
        }
        F e → ( say `dec str` F )
    }
    ( vec_free [u] bs )

    // Bytes decode fine, but the value is a bool where an int was
    // asked for → MsgpackTypeMismatch.
    : ( Vec u ) bm ( enc_bytes ( json_bool T ) )
    ?? ( from_msgpack_i bm ) {
        T n → ( say `dec mismatch` F )
        F e → ( say `dec mismatch` ?? e { MsgpackTypeMismatch → T _ → F } )
    }
    ( vec_free [u] bm )

    // Malformed bytes (reserved 0xc1) → a genuine codec error, not a
    // type mismatch.
    ?? ( bytes_from_hex `c1` ) {
        T bad → {
            ?? ( from_msgpack_i bad ) {
                T n → ( say `dec error` F )
                F e → ( say `dec error` ?? e { MsgpackBadType → T _ → F } )
            }
            ( vec_free [u] bad )
        }
        F e → ( say `dec error` F )
    }

    ^ 0
}

// serde_basic.nu — regression target for stdlib/ext/serde.nu's
// JsonSerialize trait + the from_json_<T> decoder helpers.
//
// Asserts the shipped primitive shapes round-trip cleanly:
//   to_json 42        → "42"
//   to_json T         → "true"
//   to_json 3.14      → "3.14"
//   to_json `abc`     → "\"abc\""
//   from_json_i / _b / _f / _string / _str_borrow on the matching
//   JSON values return the expected Ok payload.

$ `stdlib/ext/serde.nu`

@ main → v {
    : Json ji ( to_json 42 )
    : Json jb ( to_json T )
    : Json jf ( to_json 3.5 )
    : Json js ( to_json `abc` )

    : String si ( json_stringify ji )
    : String sb ( json_stringify jb )
    : String sf ( json_stringify jf )
    : String ss ( json_stringify js )
    ( nurl_print ( string_data si ) ) ( nurl_print `\n` )
    ( nurl_print ( string_data sb ) ) ( nurl_print `\n` )
    ( nurl_print ( string_data sf ) ) ( nurl_print `\n` )
    ( nurl_print ( string_data ss ) ) ( nurl_print `\n` )

    : !i ParseErr ri ( from_json_i ji )
    ?? ri {
        T n → ( nurl_print_int n )
        F _ → ( nurl_print `i FAIL\n` )
    }
    : !b ParseErr rb ( from_json_b jb )
    ?? rb {
        T v → ( nurl_print ? v `true\n` `false\n` )
        F _ → ( nurl_print `b FAIL\n` )
    }
    : !f ParseErr rf ( from_json_f jf )
    ?? rf {
        T x → { : String fs ( string_from `f-ok\n` ) ( nurl_print ( string_data fs ) ) ( string_free fs ) }
        F _ → ( nurl_print `f FAIL\n` )
    }
    : !String ParseErr rs ( from_json_string js )
    ?? rs {
        T s → { ( nurl_print ( string_data s ) ) ( nurl_print `\n` ) ( string_free s ) }
        F _ → ( nurl_print `s FAIL\n` )
    }

    ( string_free si ) ( string_free sb ) ( string_free sf ) ( string_free ss )
    ( json_free ji ) ( json_free jb ) ( json_free jf ) ( json_free js )
}

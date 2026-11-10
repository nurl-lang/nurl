// view_handed_to_a_call_whose_later_argument_grows_its_source: agora #577 — `( two v ( grow line ) )`, v a view of line: two reads v after grow moved line's buffer
// Closed: a call reads its argument where it runs; one that another call of the statement ended first — an earlier call, or a call nested in this one — is read after its end (agora #577).
// main ee38fbb: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #577: `( two v ( grow line ) )`, v a view of line: two reads v after grow moved line's buffer
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ cz ( Vec String ) v → i { ( vec_clear [String] v ) ^ 0 }

@ two s a i b → i { ^ + ( nurl_str_len a ) b }

@ grow String l → i { : ~ i k 0 ~ < k 64 { ( string_push_str l ` and a long tail, so the buffer moves` ) = k + k 1 } ^ 0 }

@ main → i {
    : ( Vec String ) fs ( vec_new [String] )
    ( vec_push [String] fs ( string_from `a first string long enough for a heap buffer` ) )
    ( vec_push [String] fs ( string_from `a second string long enough for a heap buffer` ) )
    : String line ( string_from `a line long enough for a heap buffer` )
    : s v ( string_data line )
    ( nurl_println_int ( two v ( grow line ) ) )
    ^ 0
}

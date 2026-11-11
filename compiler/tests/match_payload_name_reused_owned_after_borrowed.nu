// match_payload_name_reused_owned_after_borrowed.nu — agora #703: a `??`
// payload is a fresh binding each time its arm runs, and what an earlier
// payload of the same name borrowed is not what this one does. An owned
// payload `v` bound after a borrowed `v` was taken for the borrow: the
// binding it was assigned to (`= bytes v`, or the value join's `T v → v`)
// became a borrow of the earlier scrutinee, and handing it on was refused
// ("'bytes' is a borrow … released or handed over here as if it owned the
// value"). Renaming either payload made the program compile.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`
$ `stdlib/std/encode.nu`

: S { String name i n }

@ mks i k → S {
    ^ @ S { ( string_from `an owned value long enough for a heap buffer` ) k }
}

@ mko i k → ?S {
    ^ @ ?S { T ( mks k ) }
}

@ take sink ( Vec u ) bytes → i {
    ^ ( vec_len [u] bytes )
}

@ eat sink S x → i {
    ^ . x n
}

// A borrowed payload in a value join, then an owned one assigned out.
@ decoded ( Vec String ) args → i {
    : s b64 ?? ( vec_get [String] args 0 ) { T v → ( string_data v ) F → `` }
    : ~ ( Vec u ) bytes ( vec_new [u] )
    : ~ b got F
    ?? ( b64_decode_vec b64 ) {
        T v → { = bytes v = got T }
        F e → {}
    }
    ? ! got { ^ -1 } {}
    ^ ( take bytes )
}

// A borrowed payload in a statement arm, then an owned one out of a value join.
@ joined ( Vec String ) args → i {
    : ~ i ln 0
    ?? ( vec_get [String] args 0 ) { T v → { = ln ( string_len v ) } F → {} }
    : ( Vec u ) bytes ?? ( b64_decode_vec `aGVsbG8gd29ybGQ=` ) { T v → v F e → ( vec_new [u] ) }
    ^ + ln ( take bytes )
}

// The earlier payload's view is still read after the owned one is handed on.
@ kept ( Vec S ) va → i {
    : s keep ?? ( vec_get [S] va 0 ) { T v → ( string_data . v name ) F → `` }
    : ~ S a ( mks 0 )
    ?? ( mko 3 ) { T v → { = a v } F → {} }
    : i r ( eat a )
    ( nurl_println keep )
    ^ r
}

// In a loop: borrowed and owned payloads of one name, round after round.
@ rounds ( Vec S ) va → i {
    : ~ i k 0
    : ~ i t 0
    ~ < k ( vec_len [S] va ) {
        ?? ( vec_get [S] va k ) { T v → { = t + t . v n } F → {} }
        : ~ S a ( mks 0 )
        ?? ( mko k ) { T v → { = a v } F → {} }
        = t + t ( eat a )
        = k + k 1
    }
    ^ t
}

@ main → i {
    : ( Vec String ) args ( vec_new [String] )
    ( vec_push [String] args ( string_from `aGVsbG8gd29ybGQsIHRoaXMgaXMgYSBsb25nIGVub3VnaCBzdHJpbmc=` ) )
    ( nurl_println ( nurl_str_int ( decoded args ) ) )
    ( nurl_println ( nurl_str_int ( joined args ) ) )
    : ( Vec S ) va ( vec_new [S] )
    ( vec_push [S] va ( mks 10 ) )
    ( vec_push [S] va ( mks 20 ) )
    ( nurl_println ( nurl_str_int ( kept va ) ) )
    ( nurl_println ( nurl_str_int ( rounds va ) ) )
    ^ 0
}

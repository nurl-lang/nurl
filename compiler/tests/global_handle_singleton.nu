// global_handle_singleton.nu — a handle cached in a global (`= g # i v`,
// handed out again as `^ # ( Vec T ) g`) is managed by hand from the
// moment its address is stored: the binding stops owning it, and `^ v`
// lends it. Taken for owned, the first caller freed the Vec the global
// still pointed to, and every later call used freed memory.
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: ~ i g_v 0

@ cache → ( Vec String ) {
    ? != g_v 0 { ^ # ( Vec String ) g_v } {}
    : ( Vec String ) v ( vec_new [String] )
    = g_v # i v
    ^ v
}

@ remember s word → i {
    : ( Vec String ) v ( cache )
    ( vec_push [String] v ( string_from word ) )
    ^ ( vec_len [String] v )
}

@ main → i {
    ( remember `a` )
    ( remember `b` )
    ( nurl_print_int ( remember `c` ) ) ( nurl_print `\n` )
    ^ 0
}

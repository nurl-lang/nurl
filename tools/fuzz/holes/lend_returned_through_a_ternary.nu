// lend_returned_through_a_ternary: h311 through a `?` ternary (`^ ? c ( vec_get v 0 ) @ ?String { F }`): the arm's lend was not the function's.
// Closed: as h311 — gen_cond records each lending arm's call too.
// main (before this PR): AddressSanitizer reported heap-use-after-free reading the element after the release.
// map: §7.6 | A2 | rejected | h312 | h311 through a ? ternary
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ get ( Vec String ) v s key → ?String {
    ^ ? == ( nurl_str_len key ) 1 ( vec_get [String] v 0 ) @ ?String { F }
}

@ main → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `alpha` ) )
    ?? ( get v `a` ) { T x → { ( string_free x ) } F → {} }
    ( nurl_println ( string_data ( vec_at [String] v 0 ) ) )
    ^ 0
}

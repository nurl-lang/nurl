// borrow_store_consume.nu — a value stored into an aggregate belongs to
// the aggregate: consuming the old name afterwards is a second release.
//
// `@ W { x }` moves x's handle into the literal (docs/MEMORY.md §7.6); the
// literal's owner drops it — as a Vec does the element vec_push stored.
// Freeing x as well — or storing it into a
// second owner — frees the buffer twice. Reading x stays legal (the
// aggregate keeps the value alive), and a literal built as an argument to
// a function that only reads it moves nothing. The error cases are one
// per function, since recovery is per declaration; the legal spellings
// are in store_then_read_ok.nu.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { String s }

@ free_after_store → i {
    : String x ( string_from `a` )
    : W w @ W { x }
    ( string_free x )
    ^ ( string_len . w s )
}

@ store_twice → i {
    : String x ( string_from `b` )
    : W a @ W { x }
    : W b @ W { x }
    ^ + ( string_len . a s ) ( string_len . b s )
}

@ free_after_kept_argument → i {
    : ( Vec W ) ws ( vec_new [W] )
    : String x ( string_from `c` )
    ( vec_push [W] ws @ W { x } )
    ( string_free x )
    ^ ( vec_len [W] ws )
}

@ free_after_push → i {
    : ( Vec String ) vs ( vec_new [String] )
    : String x ( string_from `d` )
    ( vec_push [String] vs x )
    ( string_free x )
    ^ ( vec_len [String] vs )
}

@ main → i {
    ^ + + + ( free_after_store ) ( store_twice ) ( free_after_kept_argument ) ( free_after_push )
}

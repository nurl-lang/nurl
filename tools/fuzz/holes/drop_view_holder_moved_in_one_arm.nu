// drop_view_holder_moved_in_one_arm: agora #252 — the same with the W moved in one arm of a `??` (drop_view_holder_moved_in_one_arm).
// Closed: a holder whose drop may read views, moved on some paths only, is still dropped on the others, so the drop check asks it as one that lives (bck_deps_end, bck_borrow_end: the maybe-moved case; formal's DtorSafe join rule, agora #252).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #252: the same with the W moved in one arm of a `??`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ eat sink W w → i { ^ 0 }

@ main → i {
    : ~ String s ( string_from `a long string that the loop below grows until its buffer moves` )
    : W w @ W { ( string_data s ) }
    : ?i o ( vec_get [i] ( vec_new [i] ) 0 )
    ?? o { T x → { : i n ( eat w ) } F → {} }
    ~ < ( string_len s ) 4000 { ( string_push_str s `more and more and more text` ) }
    ^ 0
}

// drop_view_holder_moved_on_one_path_realloc: agora #252 — a W moved to a `sink` on one branch of a `?`, its String source reallocated after the join (drop_view_holder_moved_on_one_path_realloc).
// Closed: a holder whose drop may read views, moved on some paths only, is still dropped on the others, so the drop check asks it as one that lives (bck_deps_end, bck_borrow_end: the maybe-moved case; formal's DtorSafe join rule, agora #252).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #252: a W moved to a `sink` on one branch of a `?`, its String source reallocated after the join
$ `stdlib/core/string.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ eat sink W w → i { ^ 0 }

@ main → i {
    : ~ String s ( string_from `a long string that the loop below grows until its buffer moves` )
    : W w @ W { ( string_data s ) }
    : i c ( string_len s )
    ? > c 1000 { : i n ( eat w ) } {}
    ~ < ( string_len s ) 4000 { ( string_push_str s `more and more and more text` ) }
    ^ 0
}

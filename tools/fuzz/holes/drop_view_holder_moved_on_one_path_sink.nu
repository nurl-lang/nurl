// drop_view_holder_moved_on_one_path_sink: agora #252 — the same with the source handed to a `sink` after the join (drop_view_holder_moved_on_one_path_sink).
// Closed: a holder whose drop may read views, moved on some paths only, is still dropped on the others, so the drop check asks it as one that lives (bck_deps_end, bck_borrow_end: the maybe-moved case; formal's DtorSafe join rule, agora #252).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #252: the same with the source handed to a `sink` after the join
$ `stdlib/core/string.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ eat sink W w → i { ^ 0 }

@ take sink String s → i { ^ ( string_len s ) }

@ main → i {
    : String s ( string_from `a long string handed away after the join` )
    : W w @ W { ( string_data s ) }
    : i c ( string_len s )
    ? > c 1000 { : i n ( eat w ) } {}
    : i k ( take s )
    ^ 0
}

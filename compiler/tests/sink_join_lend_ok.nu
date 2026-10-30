// sink_join_lend_ok.nu — a `?` / `??` handed to a `sink` parameter, bare
// or as a block's tail, whose arm lends a local: the callee is handed a
// copy on the paths where the join lends, and the fresh arm moves. The
// local still holds its string afterwards, and its drop runs once.

$ `stdlib/core/string.nu`

: W { String s i n }

% Drop W { @ drop W w → v { ( nurl_print `drop ` ) ( nurl_println_int . w n ) } }

@ gets W w → String { ^ . w s }

@ mkw i n → W { ^ @ W { ( string_from `a string lent out of a local` ) n } }

@ keep sink String t → i { ^ ( string_len t ) }

@ run b c → v {
    : W w ( mkw ? c 1 2 )
    ( nurl_println_int ( keep ? c ( gets w ) ( string_from `fresh` ) ) )
    ( nurl_println_int ( keep { : i k 1 ? c ( gets w ) ( string_from `fresh` ) } ) )
    ( nurl_println ( string_data . w s ) )
}

@ main → i {
    ( run T )
    ( run F )
    ^ 0
}

// literal_field_moved_and_kept: a struct literal moving a binding into one field while another field hands the same binding to a callee that keeps it — `^ @ Two { t ( wrap t ) }`, `wrap` storing its parameter in what it returns — made two owners of one value: the fields of a literal run in order and their moves reach the borrow walk only after the statement, so nothing saw the second one.
// Closed: the literal's fields are checked against each other as a call's arguments are (bck_check_lit_moves): a name moved in bare may not be handed to a callee that consumes or keeps it, nor moved in twice, nor kept lent beside its move; a callee whose summary is not final yet is decided at module end (resolve_lit_handoffs).
// main (before this PR): heap-use-after-free, reading the String the second owner released.
// map: §2.12 | A2 | rejected | h205 | struct literal moves t into a field and passes t to a keeper in another
$ `stdlib/core/string.nu`

: Holder { String h }
: Two { String a Holder b }

@ wrap String x → Holder { ^ @ Holder { x } }

@ mk → Two {
    : String t ( string_from `seven` )
    ^ @ Two { t ( wrap t ) }
}

@ main → i {
    : Two w ( mk )
    ( nurl_print ( string_data . w a ) )
    ( nurl_print `\n` )
    ^ 0
}

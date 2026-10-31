// drop_view_source_moved: agora #224 — the same with s handed to a `sink` callee while w views it (drop_view_source_moved).
// Closed: the scope-end drop of a binding whose type runs a destructor of the program's own that may read a view (__drop_may_read_view) is a use of what the view points into, so a source of its views that ends first — reallocated, moved, out of scope, or dropped before it at a return — is refused where it ends (bck_drop_view_diag, bck_ret_drop_check; agora #224).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #224: the same with s handed to a `sink` callee while w views it
$ `stdlib/core/string.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ take sink String s → i { ^ ( string_len s ) }

@ main → i {
    : String s ( string_from `a string handed away while w still views it` )
    : W w @ W { ( string_data s ) }
    : i n ( take s )
    ^ 0
}

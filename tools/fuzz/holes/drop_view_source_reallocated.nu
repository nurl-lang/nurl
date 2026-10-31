// drop_view_source_reallocated: agora #224 — `: W w @ W { ( string_data s ) }`, then `( string_push_str s … )` until the buffer moves: W's destructor read the old buffer (drop_view_source_reallocated).
// Closed: the scope-end drop of a binding whose type runs a destructor of the program's own that may read a view (__drop_may_read_view) is a use of what the view points into, so a source of its views that ends first — reallocated, moved, out of scope, or dropped before it at a return — is refused where it ends (bck_drop_view_diag, bck_ret_drop_check; agora #224).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #224: `: W w @ W { ( string_data s ) }`, then `( string_push_str s … )` until the buffer moves: W's destructor read the old buffer
$ `stdlib/core/string.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ main → i {
    : ~ String s ( string_from `a long string that the loop below grows until its buffer moves` )
    : W w @ W { ( string_data s ) }
    ~ < ( string_len s ) 4000 { ( string_push_str s `more and more and more text` ) }
    ^ 0
}

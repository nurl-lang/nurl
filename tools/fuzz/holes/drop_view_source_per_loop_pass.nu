// drop_view_source_per_loop_pass: agora #224 — w, outside a loop, given a view of a String made in each pass (drop_view_source_per_loop_pass).
// Closed: the scope-end drop of a binding whose type runs a destructor of the program's own that may read a view (__drop_may_read_view) is a use of what the view points into, so a source of its views that ends first — reallocated, moved, out of scope, or dropped before it at a return — is refused where it ends (bck_drop_view_diag, bck_ret_drop_check; agora #224).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #224: w, outside a loop, given a view of a String made in each pass
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ main → i {
    : ~ W w @ W { `literal` }
    : ~ i k 0
    ~ < k 3 {
        : String s ( string_from `a source made in each pass of a loop` )
        = w @ W { ( string_data s ) }
        = k + k 1
    }
    ^ 0
}

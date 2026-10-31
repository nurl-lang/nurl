// drop_view_slice_holder_declared_first: agora #224 — a W holding a Slice of a Vec declared after it (drop_view_slice_holder_declared_first).
// Closed: the scope-end drop of a binding whose type runs a destructor of the program's own that may read a view (__drop_may_read_view) is a use of what the view points into, so a source of its views that ends first — reallocated, moved, out of scope, or dropped before it at a return — is refused where it ends (bck_drop_view_diag, bck_ret_drop_check; agora #224).
// main: accepted and ran clean only because it dropped in declaration order.
// map: §7.6 | A2 | rejected | - | agora #224: a W holding a Slice of a Vec declared after it
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: W { ( Slice u ) sl }

% Drop W { @ drop W self → v { ?? ( slice_get [u] . self sl 3 ) { T b → ( nurl_println_int # i b ) F _ → {} } } }

@ main → i {
    : ~ W w @ W { ( slice_empty [u] ) }
    : ( Vec u ) v ( vec_zeroed [u] 64 )
    = w @ W { ( slice_from_vec [u] v ) }
    ^ 0
}

// drop_view_holder_moved_on_one_path_inner_scope: agora #252 — a W outside a block, given a view of the block's String and moved on one branch inside it (drop_view_holder_moved_on_one_path_inner_scope).
// Closed: a holder whose drop may read views, moved on some paths only, is still dropped on the others, so the drop check asks it as one that lives (bck_deps_end, bck_borrow_end: the maybe-moved case; formal's DtorSafe join rule, agora #252).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #252: a W outside a block, given a view of the block's String and moved on one branch inside it
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ eat sink W w → i { ^ 0 }

@ main → i {
    : ~ W w @ W { `literal` }
    {
        : String s ( string_from `a string that ends with the inner block` )
        = w @ W { ( string_data s ) }
        ? > ( string_len s ) 1000 { : i n ( eat w ) } {}
    }
    ^ 0
}

// drop_view_dyn_impl_reads: agora #224 — a `% Show` object over a type whose `% Drop` reads its view, kept past the String it views (drop_view_dyn_impl_reads).
// Closed: the scope-end drop of a binding whose type runs a destructor of the program's own that may read a view (__drop_may_read_view) is a use of what the view points into, so a source of its views that ends first — reallocated, moved, out of scope, or dropped before it at a return — is refused where it ends (bck_drop_view_diag, bck_ret_drop_check; agora #224).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #224: a `% Show` object over a type whose `% Drop` reads its view, kept past the String it views
$ `stdlib/core/string.nu`

% Show [T] {
    @ len T self → i
}

: V { s p i pad }

% Drop V { @ drop V self → v { ( nurl_println . self p ) } }

% Show V { @ len V v → i { ^ ( nurl_str_len . v p ) } }

@ main → i {
    : ~ % Show r ( dyn Show @ V { `static` 0 } )
    {
        : String s ( string_from `a string long enough to own a heap buffer here` )
        = r ( dyn Show @ V { ( string_data s ) 0 } )
    }
    ^ 0
}

// drop_view_dyn_impl_without_destructor: agora #224 — a `% Show` object over a struct of views with no `% Drop`, kept past its source and never read (drop_view_dyn_impl_without_destructor).
// Kept: a holder whose drop reads nothing is not affected by the rule (agora #224).
// main: accepted; ran clean.
// map: §7.6 | A2 | runs-clean | - | agora #224: a `% Show` object over a struct of views with no `% Drop`, kept past its source and never read
$ `stdlib/core/string.nu`

% Show [T] {
    @ len T self → i
}

: V { s p i pad }

% Show V { @ len V v → i { ^ ( nurl_str_len . v p ) } }

@ main → i {
    : ~ % Show r ( dyn Show @ V { `static` 0 } )
    {
        : String s ( string_from `a string long enough to own a heap buffer here` )
        = r ( dyn Show @ V { ( string_data s ) 0 } )
    }
    ^ 0
}

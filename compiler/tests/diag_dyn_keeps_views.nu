// diag_dyn_keeps_views.nu — a trait object over a struct of views points
// where the struct did (agora #156): returned, or kept past the String it
// views, it reads freed memory.

$ `stdlib/core/string.nu`

% Show [T] {
    @ len T self → i
}

: V { s p i pad }

: W { V v i n }

% Show V { @ len V v → i { ^ ( nurl_str_len . v p ) } }

@ bound_then_returned → %Show {
    : String s ( string_from `a string long enough to own a heap buffer here` )
    : V v @ V { ( string_data s ) 0 }
    ^ ( dyn Show v )
}

@ a_field_returned → %Show {
    : String s ( string_from `a string long enough to own a heap buffer here` )
    : W w @ W { @ V { ( string_data s ) 0 } 1 }
    ^ ( dyn Show . w v )
}

@ main → i {
    : ~ % Show r ( dyn Show @ V { `static` 0 } )
    {
        : String s ( string_from `a string long enough to own a heap buffer here` )
        = r ( dyn Show @ V { ( string_data s ) 0 } )
    }
    ^ ( len r )
}

// diag_raw_string_in_value.nu — a raw string held by a struct, an option,
// an enum, a slice or a container is a view in safe code (docs/MEMORY.md
// §2.13): it owns nothing. A fresh string — a call's result that hands its
// string over — stored there, or handed to a parameter that keeps it, would
// be released by no one, and is rejected where it is stored: a struct
// literal's field, an option payload, a slice element, an assigned field,
// and an owned local handed back in a struct (tools/fuzz/holes h129–h140;
// what a callee keeps, and what a call answering per call may hand over,
// are decided at module end: diag_raw_string_kept). The controls compile:
// a String field, a view of a binding, a literal.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Rec { s name i n }

: Named { String name i n }

@ in_literal → i {
    : Rec r @ Rec { ( nurl_str_cat `a` `b` ) 1 }
    ^ . r n
}

@ in_option → i {
    : ?s o @ ?s { T ( nurl_str_cat `a` `b` ) }
    ^ 0
}

@ in_slice → i {
    : [s xs [s | ( nurl_str_cat `a` `b` ) `c`]
    ^ . xs 1
}

@ assigned → i {
    : ~ Rec r @ Rec { `x` 1 }
    = . r name ( nurl_str_cat `a` `b` )
    ^ . r n
}

@ handed_back s a → Rec {
    : s x ( nurl_str_cat a `b` )
    ^ @ Rec { x 1 }
}

@ string_field → i {
    : Named r @ Named { ( string_from `a` ) 1 }
    ^ ( string_len . r name )
}

@ view_of_binding → i {
    : s x ( nurl_str_cat `a` `b` )
    : Rec r @ Rec { x 1 }
    ^ ( nurl_str_len . r name )
}

@ literal_field → i {
    : Rec r @ Rec { `abc` 1 }
    ^ ( nurl_str_len . r name )
}

@ main → i {
    : Rec h ( handed_back `a` )
    ^ + + + + + + ( in_literal ) ( in_option ) ( in_slice ) ( assigned ) ( string_field ) ( view_of_binding ) ( literal_field )
}

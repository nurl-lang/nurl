// lend_through_views_valid_shapes.nu — the valid side of agora #594, #590,
// #596, #578 and #679 (docs/MEMORY.md §2.8, §2.10): what a function hands
// back out of a view of its parameter — an element read through a Slice it
// built, through a view field of a struct of views, a field of a call's
// result, a bare `s` view of a `??` payload — is lent, and a caller that
// reads the result before it ends the argument, or copies it, is accepted
// and runs clean. A call that is fresh on one path and lent on the other
// answers per call; one whose every value is a lend still lends; one that
// always hands over its own makes its matched payload the owner.
//
// The controls for the diag_lend_* and diag_view_of_may_owned_result_*
// tests, which pin the refusals.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/option.nu`

: S { String name i n }
: Q { ( Slice S ) z i k }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

@ mkv2 → ( Vec S ) {
    : ( Vec S ) v ( vec_new [S] )
    ( vec_push [S] v ( mks `first element, long enough for a heap buffer` ) )
    ( vec_push [S] v ( mks `second element, long enough for a heap buffer` ) )
    ^ v
}

// agora #594: an element read through a Slice built over the parameter.
@ through_slice ( Vec S ) va → S {
    : ( Slice S ) sl ( slice_from_vec [S] va )
    ^ ( slice_at [S] sl 1 )
}

// agora #590: an element read through the view field of a struct of views.
@ through_field Q q → S {
    : ( Slice S ) z . q z
    ^ ( slice_at [S] z 0 )
}

// agora #596: a field of a call's result.
@ name_of ( Vec S ) va → String { ^ . ( vec_at [S] va 0 ) name }

// agora #578: a bare `s` view of a `??` payload, out of a value join.
@ first_name ( Vec S ) va → s {
    ^ ?? ( vec_get [S] va 0 ) {
        T e → ( string_data . e name )
        F → `(empty)`
    }
}

// agora #679: fresh on one path, lent on the other — the answer is per call.
@ pick ( Vec S ) va b own → ?S {
    ? own { ^ @ ?S { T ( mks `a fresh value made by pick, long enough for a heap buffer` ) } } {}
    : ?S found ( vec_get [S] va 0 )
    ^ found
}

// … so its caller keeps what it reads out of the result for itself.
@ picked_len ( Vec S ) va b own → i {
    : ?S o ( pick va own )
    ?? o {
        T e → { ^ ( string_len . e name ) }
        F → { ^ -1 }
    }
    ^ -1
}

// A find loop: every value the binding is given is a lend or holds
// nothing, so `find` lends and its caller may hand a view on.
@ find ( Vec S ) va i want → ?S {
    : ~ ? S found @ ?S { F @ S { ( string_new ) 0 } }
    : ~ i k 0
    ~ < k ( vec_len [S] va ) {
        : ?S ev ( vec_get [S] va k )
        ? == k want { = found ev } {}
        = k + k 1
    }
    ^ found
}

@ found_name ( Vec S ) va i want → s {
    : ?S o ( find va want )
    ?? o {
        T e → { ^ ( string_data . e name ) }
        F → { ^ `(none)` }
    }
    ^ `(none)`
}

// A call that hands over a value of its own on every call: the payload
// matched straight out of it is that value's owner and may be moved on.
@ make b some → ?S {
    ? some { ^ @ ?S { T ( mks `made here, long enough for a heap buffer` ) } } {}
    ^ @ ?S { F @ S { ( string_new ) 0 } }
}

@ remake b some → ?S {
    ?? ( make some ) {
        T e → { ^ @ ?S { T e } }
        F → {}
    }
    ^ @ ?S { F @ S { ( string_new ) 0 } }
}

@ main → i {
    : ~ ( Vec S ) va ( mkv2 )
    : S a ( through_slice va )
    ( nurl_println ( string_data . a name ) )
    : Q q @ Q { ( slice_from_vec [S] va ) 1 }
    : S c ( through_field q )
    ( nurl_println ( string_data . c name ) )
    : String nm ( name_of va )
    ( nurl_println ( string_data nm ) )
    ( nurl_println ( first_name va ) )
    ( nurl_println ( nurl_str_int ( picked_len va T ) ) )
    ( nurl_println ( nurl_str_int ( picked_len va F ) ) )
    ( nurl_println ( found_name va 1 ) )
    ( nurl_println ( found_name va 7 ) )
    // A copy is the caller's own: it outlives the Vec's clear.
    : S kept ( mem_dup ( through_slice va ) )
    ( vec_clear [S] va )
    ( nurl_println ( string_data . kept name ) )
    ( nurl_println ( first_name va ) )
    ?? ( remake T ) {
        T e → { ( nurl_println ( string_data . e name ) ) }
        F → { ( nurl_println `(nothing made)` ) }
    }
    ?? ( remake F ) {
        T e → { ( nurl_println ( string_data . e name ) ) }
        F → { ( nurl_println `(nothing made)` ) }
    }
    ^ 0
}

// panic_in_drop_at_function_exit.nu — a local's destructor panics while a
// function that has already evaluated its result drops its locals (Agora
// #612; formal/CLAIM.md, the call's result frame).
//
// The result is the function's own until the `ret`: a panic in one of its
// locals' destructors runs the result's destructor (once) and frees what
// the result owns, then goes on to the `recover`. Before, the result lived
// only in a register while the locals were dropped, in no journal entry:
// `drop result` never ran, and the result's memory leaked (LeakSanitizer,
// run_san_tests.sh). A binding handed back (`^ res`) was lost the same way
// when it was declared after the local whose destructor panics: its
// registration ended first, in list order.
//
// The same holds for a literal handed back that took in a binding of the
// function (`^ @ ?Bomb { T k }`, Agora #720: the binding's own registration
// had let go of the value, and the literal was in none), for a result held
// through a `;` defer chain that panics, and for a fresh raw string or a
// closure handed back (Agora #620).

$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb {
    @ drop Bomb b → v {
        ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) )
        ? == . b boom 1 { ( panic ( nurl_str_cat `panic in drop ` ( string_data . b tag ) ) ) } {}
    }
}

: Holder { String name Bomb inner }

@ bomb s tag i boom → Bomb { ^ @ Bomb { ( string_from tag ) boom } }

// A literal.
@ lit → Bomb {
    : Bomb loc ( bomb `lit.local` 1 )
    ^ @ Bomb { ( string_from `lit.result` ) 0 }
}

// A call's value.
@ call → Bomb {
    : Bomb loc ( bomb `call.local` 1 )
    ^ ( bomb `call.result` 0 )
}

// A binding declared after the local that panics, and one declared before.
@ bind_after → Bomb {
    : Bomb loc ( bomb `after.local` 1 )
    : Bomb res ( bomb `after.result` 0 )
    ^ res
}

@ bind_before → Bomb {
    : Bomb res ( bomb `before.result` 0 )
    : Bomb loc ( bomb `before.local` 1 )
    ^ res
}

// A `?` join of two fresh values.
@ join i c → Bomb {
    : Bomb loc ( bomb `join.local` 1 )
    ^ ? == c 1 ( bomb `join.result-a` 0 ) ( bomb `join.result-b` 0 )
}

// The body's last expression, with no `^`.
@ falloff → Bomb {
    : Bomb loc ( bomb `falloff.local` 1 )
    @ Bomb { ( string_from `falloff.result` ) 0 }
}

// A struct holding a `% Drop` field: the compiler's drop of its fields.
@ holder → Holder {
    : Bomb loc ( bomb `holder.local` 1 )
    ^ @ Holder { ( string_from `a holder's name, long enough for the heap` ) ( bomb `holder.inner` 0 ) }
}

// Results with no destructor of their own: plain leaks before.
@ text → String {
    : Bomb loc ( bomb `text.local` 1 )
    ^ ( string_from `a result string that lives on the heap` )
}

@ list → ( Vec String ) {
    : Bomb loc ( bomb `list.local` 1 )
    : ~ ( Vec String ) out ( vec_new [String] )
    ( vec_push [String] out ( string_from `an element of the result` ) )
    ^ out
}

// Two locals, both panicking: the second panic is inside the first's
// drain, and the result is still dropped once.
@ two → Bomb {
    : Bomb l1 ( bomb `two.local-1` 1 )
    : Bomb l2 ( bomb `two.local-2` 1 )
    ^ ( bomb `two.result` 0 )
}

// A value the caller LENT, handed back as it is — the element a `~` loop
// is at, in the caller's Vec — is not the function's to drop: the panic
// leaves it where it lives, and the caller's Vec drops it, once.
@ lent_elem ( Vec Bomb ) v → Bomb {
    : Bomb loc ( bomb `lent.local` 1 )
    ~ x v { ? == . x boom 0 { ^ x } {} }
    ^ ( vec_at [Bomb] v 0 )
}

@ lent_caller → v {
    : ~ ( Vec Bomb ) v ( vec_new [Bomb] )
    ( vec_push [Bomb] v ( bomb `lent.e0` 0 ) )
    ( vec_push [Bomb] v ( bomb `lent.e1` 0 ) )
    : Bomb r ( lent_elem v )
    ( nurl_println `not reached` )
}

// No panic: the result reaches the caller, and is dropped there, once.
@ quiet → Bomb {
    : Bomb loc ( bomb `quiet.local` 0 )
    ^ ( bomb `quiet.result` 0 )
}

// A literal that took in bindings of the function (Agora #720): an option
// over one, a struct over two, a literal nested in a literal, a `sink`
// parameter.
@ lit_bind → ?Bomb {
    : Bomb loc ( bomb `litbind.local` 1 )
    : Bomb k ( bomb `litbind.result` 0 )
    ^ @ ?Bomb { T k }
}

@ lit_two → Holder {
    : Bomb loc ( bomb `littwo.local` 1 )
    : String name ( string_from `a holder's name, long enough for the heap` )
    : Bomb inner ( bomb `littwo.inner` 0 )
    ^ @ Holder { name inner }
}

@ lit_nested → ?Holder {
    : Bomb loc ( bomb `litnest.local` 1 )
    : Bomb inner ( bomb `litnest.inner` 0 )
    ^ @ ?Holder { T @ Holder { ( string_from `a nested holder's name` ) inner } }
}

@ lit_sink sink Bomb p → ?Bomb {
    : Bomb loc ( bomb `litsink.local` 1 )
    ^ @ ?Bomb { T p }
}

// A `;` defer that panics after the result is set (Agora #620): a literal,
// a binding.
@ defer_lit → Bomb {
    ; { ( panic `panic in a defer` ) }
    ^ @ Bomb { ( string_from `deferlit.result` ) 0 }
}

@ defer_bind → Bomb {
    : Bomb r ( bomb `deferbind.result` 0 )
    ; { ( panic `panic in a defer` ) }
    ^ r
}

// A fresh raw string, a closure literal, a closure a call made (Agora #620).
@ raw_text → s {
    : Bomb loc ( bomb `raw.local` 1 )
    ^ ( nurl_str_cat `a raw result string, ` `concatenated on the heap` )
}

@ clo_lit → ( @ i ) {
    : Bomb loc ( bomb `clolit.local` 1 )
    : Bomb cap ( bomb `clolit.capture` 0 )
    ^ \ → i { ^ . cap boom }
}

@ mk_clo → ( @ i ) {
    : Bomb cap ( bomb `clocall.capture` 0 )
    ^ \ → i { ^ . cap boom }
}

@ clo_call → ( @ i ) {
    : Bomb loc ( bomb `clocall.local` 1 )
    ^ ( mk_clo )
}

@ run s name ( @ v ) f → v {
    : !v PanicInfo r ( recover f )
    ?? r {
        T _ → { ( nurl_println ( nurl_str_cat name `: no panic` ) ) }
        F e → { ( nurl_println ( nurl_str_cat3 name `: recovered: ` ( string_data . e msg ) ) ) }
    }
}

@ main → i {
    ( run `lit` \ → v { : Bomb r ( lit ) ( nurl_println `not reached` ) } )
    ( run `call` \ → v { : Bomb r ( call ) ( nurl_println `not reached` ) } )
    ( run `bind_after` \ → v { : Bomb r ( bind_after ) ( nurl_println `not reached` ) } )
    ( run `bind_before` \ → v { : Bomb r ( bind_before ) ( nurl_println `not reached` ) } )
    ( run `join` \ → v { : Bomb r ( join 1 ) ( nurl_println `not reached` ) } )
    ( run `falloff` \ → v { : Bomb r ( falloff ) ( nurl_println `not reached` ) } )
    ( run `holder` \ → v { : Holder r ( holder ) ( nurl_println `not reached` ) } )
    ( run `text` \ → v { : String r ( text ) ( nurl_println `not reached` ) } )
    ( run `list` \ → v { : ( Vec String ) r ( list ) ( nurl_println `not reached` ) } )
    ( run `two` \ → v { : Bomb r ( two ) ( nurl_println `not reached` ) } )
    ( run `lent_elem` \ → v { ( lent_caller ) } )
    ( run `quiet` \ → v { : Bomb r ( quiet ) ( nurl_println `quiet: returned` ) } )
    ( run `lit_bind` \ → v { : ?Bomb r ( lit_bind ) ( nurl_println `not reached` ) } )
    ( run `lit_two` \ → v { : Holder r ( lit_two ) ( nurl_println `not reached` ) } )
    ( run `lit_nested` \ → v { : ?Holder r ( lit_nested ) ( nurl_println `not reached` ) } )
    ( run `lit_sink` \ → v { : ?Bomb r ( lit_sink ( bomb `litsink.result` 0 ) ) ( nurl_println `not reached` ) } )
    ( run `defer_lit` \ → v { : Bomb r ( defer_lit ) ( nurl_println `not reached` ) } )
    ( run `defer_bind` \ → v { : Bomb r ( defer_bind ) ( nurl_println `not reached` ) } )
    ( run `raw_text` \ → v { : s r ( raw_text ) ( nurl_println `not reached` ) } )
    ( run `clo_lit` \ → v { : ( @ i ) r ( clo_lit ) ( nurl_println `not reached` ) } )
    ( run `clo_call` \ → v { : ( @ i ) r ( clo_call ) ( nurl_println `not reached` ) } )
    ^ 0
}

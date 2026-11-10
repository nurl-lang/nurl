// panic_in_drop_of_struct_field.nu — a field's (or a payload's) destructor
// panics while the compiler-written drop glue releases a struct or an enum
// (Agora #617).
//
// The parts after it are still dropped: their destructors run, in field
// order and once each, and what they own is freed, before the panic goes
// on to its `recover`. Before, the glue was simply left: `drop z` never
// ran, and a plain `String` or `Vec` field after the panicking one leaked
// (LeakSanitizer, run_san_tests.sh). The same for the later payloads of
// an enum's variant, and for the box a payload lives in.

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

@ bomb s tag i boom → Bomb { ^ @ Bomb { ( string_from tag ) boom } }

// Sibling destructor fields.
: Three { Bomb x Bomb y Bomb z }

@ siblings → v {
    : Three t @ Three { ( bomb `x` 0 ) ( bomb `y` 1 ) ( bomb `z` 0 ) }
    ( nurl_println `siblings: built` )
}

// Plain owned fields after the one that panics.
: Holder { Bomb x String name ( Vec String ) items ? String note }

@ plain_after → v {
    : ~ ( Vec String ) it ( vec_new [String] )
    ( vec_push [String] it ( string_from `an item on the heap, long enough` ) )
    : Holder h @ Holder { ( bomb `h.x` 1 ) ( string_from `a name on the heap, long enough` ) it @ ?String { T ( string_from `a note on the heap, long enough` ) } }
    ( nurl_println `plain_after: built` )
}

// A struct of structs, a panic in each: the second is inside the first's
// drain.
: Pair2 { Bomb a Bomb b }

: Outer { Pair2 one String name Pair2 two }

@ nested → v {
    : Outer o @ Outer { @ Pair2 { ( bomb `1a` 1 ) ( bomb `1b` 0 ) } ( string_from `between the two, on the heap` ) @ Pair2 { ( bomb `2a` 1 ) ( bomb `2b` 0 ) } }
    ( nurl_println `nested: built` )
}

// A `% Drop` struct: its impl, then its fields.
: Res { String label Bomb x Bomb y }

% Drop Res { @ drop Res r → v { ( nurl_println ( nurl_str_cat `drop res ` ( string_data . r label ) ) ) } }

@ own_drop → v {
    : Res r @ Res { ( string_from `R` ) ( bomb `r.x` 1 ) ( bomb `r.y` 0 ) }
    ( nurl_println `own_drop: built` )
}

// An enum's payloads, a payload in a box, and such values in a Vec.
: | Ev { Quiet i Loud Bomb Trio Bomb String Bomb Boxed Pair2 String }

@ payloads → v {
    : ~ ( Vec Ev ) v ( vec_new [Ev] )
    ( vec_push [Ev] v @ Ev { Quiet 1 } )
    ( vec_push [Ev] v @ Ev { Loud ( bomb `loud` 1 ) } )
    ( vec_push [Ev] v @ Ev { Trio ( bomb `t1` 1 ) ( string_from `the middle payload, on the heap` ) ( bomb `t3` 1 ) } )
    ( vec_push [Ev] v @ Ev { Boxed @ Pair2 { ( bomb `ba` 1 ) ( bomb `bb` 0 ) } ( string_from `after the box, on the heap` ) } )
    ( nurl_println `payloads: built` )
}

// No panic: every part once, in order.
@ quiet → v {
    : Three t @ Three { ( bomb `q.x` 0 ) ( bomb `q.y` 0 ) ( bomb `q.z` 0 ) }
    : Ev e @ Ev { Trio ( bomb `q.t1` 0 ) ( string_from `quiet` ) ( bomb `q.t3` 0 ) }
}

@ run s name ( @ v ) f → v {
    : !v PanicInfo r ( recover f )
    ?? r {
        T _ → { ( nurl_println ( nurl_str_cat name `: no panic` ) ) }
        F e → { ( nurl_println ( nurl_str_cat3 name `: recovered: ` ( string_data . e msg ) ) ) }
    }
}

@ main → i {
    ( run `siblings` \ → v { ( siblings ) } )
    ( run `plain_after` \ → v { ( plain_after ) } )
    ( run `nested` \ → v { ( nested ) } )
    ( run `own_drop` \ → v { ( own_drop ) } )
    ( run `payloads` \ → v { ( payloads ) } )
    ( run `quiet` \ → v { ( quiet ) } )
    ( quiet )
    ^ 0
}

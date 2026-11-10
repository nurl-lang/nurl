// assignment_to_a_vec_whose_old_elements_destructor_panics_leaves_the_owner_the_freed_vec: `= v other` over a Vec (or an owned slice) of `% Drop` values released the old one in place before the store: an element's destructor that panicked under `recover` left the binding holding the freed old handle — the unwind read it, and an owner outside the recover extent read it and freed it again.
// Closed: an assignment takes the old value out first — the new value is stored, then the old one is dropped from a temporary (mem_replaced_drop / gen_assign) — so a panic in its destructor finds the target holding the new value, which is dropped once (agora #621).
// main (before this PR): AddressSanitizer heap-use-after-free (the drain through the binding's registration; `vec_len` after the recover).
// map: §7.6 | A2 | runs-clean | - | agora #621: a Vec or slice binding reassigned while an old element's destructor panics kept the freed old handle, for the unwind and for an owner outside the recover
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

@ run s name ( @ v ) f → v {
    : !v PanicInfo r ( recover f )
    ?? r {
        T _ → { ( nurl_println ( nurl_str_cat name `: no panic` ) ) }
        F e → { ( nurl_println ( nurl_str_cat3 name `: recovered: ` ( string_data . e msg ) ) ) }
    }
}

@ three s a s b s c i boom → ( Vec Bomb ) {
    : ~ ( Vec Bomb ) w ( vec_new [Bomb] )
    ( vec_push [Bomb] w ( bomb a 0 ) )
    ( vec_push [Bomb] w ( bomb b boom ) )
    ( vec_push [Bomb] w ( bomb c 0 ) )
    ^ w
}

@ vec → v {
    : ~ ( Vec Bomb ) a ( three `a` `b` `c` 1 )
    = a ( three `d` `e` `f` 0 )
    ( nurl_println `vec: not reached` )
}

@ slice → v {
    : ~ [Bomb a [Bomb | ( bomb `a` 0 ) ( bomb `b` 1 ) ( bomb `c` 0 )]
    = a [Bomb | ( bomb `d` 0 ) ( bomb `e` 0 )]
    ( nurl_println `slice: not reached` )
}

@ outer → v {
    : ~ ( Vec Bomb ) a ( three `a` `b` `c` 1 )
    ( run `outer` \ → v { = a ( three `d` `e` `f` 0 ) ( nurl_println `outer: not reached` ) } )
    ( nurl_println ( nurl_str_cat `outer: a holds ` ( nurl_str_int ( vec_len [Bomb] a ) ) ) )
    ~ x a { ( nurl_println ( nurl_str_cat `outer: ` ( string_data . x tag ) ) ) }
}

@ main → i {
    ( run `vec` \ → v { ( vec ) } )
    ( run `slice` \ → v { ( slice ) } )
    ( outer )
    ^ 0
}

// closure_arm_tail_assign.nu — a `?` arm whose last statement assigns a
// closure binding (`= base w`) yields that binding's closure, not a copy.
//
// The arm's value was taken for an owned temporary of the join and copied
// (nurl_closure_clone), but a `?` statement consumes no value: the copy —
// the wrapper's env and the clone of what it captured — leaked on every
// run (packages/http's middleware layers, `= base altw` in __httpapp_serve).

$ `stdlib/core/string.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

@ wrap ( @ i i ) inner → ( @ i i ) {
    ^ \ i x → i { ^ + ( inner x ) 1 }
}

@ run b on i k → i {
    : ( @ i i ) disp \ i x → i { ^ + x k }
    : ~ ( @ i i ) base disp
    : ~ ( @ i i ) w disp
    ? on {
        = w ( wrap base )
        = base w
    } {}
    ^ ( base 1 )
}

@ main → i {
    : i r0 ( run T 5 )
    : i before - ( nurl_alloc_count ) ( nurl_free_count )
    : ~ i n 0
    ~ < n 20 { : i r ( run T n ) = n + n 1 }
    : i after - ( nurl_alloc_count ) ( nurl_free_count )
    ( nurl_print `live delta over 20 calls: ` ) ( nurl_print_int - after before ) ( nurl_print `\n` )
    ^ 0
}

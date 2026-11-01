// journal_slot_cfg_ir.nu — the program journal_slot_cfg_ir.sh reads the IR
// of: owned handle bindings inside a recover extent, held across calls
// that can and cannot panic (agora #283). A registration is needed only
// where a panic can meet it while it is held: `early` holds a Vec across a
// call that cannot panic, and a call that can comes only after the Vec is
// gone; `across` holds a Vec across a call that can; `divided` holds a Vec
// across a division by a value it does not know, whose zero check is a
// branch to a panic.
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/panic.nu`

// Cannot panic.
@ quiet ( Vec u ) s → i {
    ^ ( vec_len [u] s )
}

// May panic: an index past the end does.
@ loud ( Vec u ) v i k → i {
    ^ # i ( vec_at [u] v k )
}

@ make → ?( Vec u ) {
    : ( Vec u ) b ( vec_new [u] )
    ( vec_push [u] b # u 1 )
    ^ @ ?( Vec u ) { T b }
}

@ early ( Vec u ) v → i {
    : ~ i n 0
    ?? ( make ) {
        T s → { = n ( quiet s ) }
        F → {}
    }
    ^ + n ( loud v 0 )
}

@ across ( Vec u ) v → i {
    : ( Vec u ) s ( make_vec )
    : i k ( loud v 0 )
    ^ + k ( quiet s )
}

@ divided i d → i {
    : ( Vec u ) s ( make_vec )
    : i q / 10 d
    ^ + q ( quiet s )
}

@ make_vec → ( Vec u ) {
    : ( Vec u ) b ( vec_new [u] )
    ( vec_push [u] b # u 2 )
    ( vec_push [u] b # u 3 )
    ^ b
}

@ main → i {
    : ( Vec u ) v ( vec_new [u] )
    ( vec_push [u] v # u 7 )
    : ~ i out 0
    : !v PanicInfo r ( recover \ → v {
        = out + + ( early v ) ( across v ) ( divided 2 )
    } )
    ( nurl_println_int out )
    // An index past the end, caught: the Vec the frame held is released by
    // the journal, and the run stays clean under LSan.
    : ( Vec u ) e ( vec_new [u] )
    : !v PanicInfo r2 ( recover \ → v {
        = out ( across e )
    } )
    ?? r2 {
        T _ → ( nurl_println `no panic` )
        F p → { ( nurl_println `caught` ) ( panic_info_free p ) }
    }
    ^ 0
}

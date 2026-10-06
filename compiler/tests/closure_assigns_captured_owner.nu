// closure_assigns_captured_owner.nu — a value a closure assigns over a
// binding it captured by pointer is owned by that binding.
//
// `: ~ Resp resp dflt … ( recover \ → v { = resp ( f req ) } )`: the closure
// wrote the caller's alloca but could not reach the binding's drop flag, so
// the old value was never dropped and the new one never owned — one
// response leaked per request (stdlib http_server's keep-alive loop). The
// env now carries the flag. A borrowed element assigned the same way stays
// borrowed.

$ `stdlib/core/vec.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe

@ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

: Resp { i status ( Vec u ) body }

@ mk i st → Resp {
    : ( Vec u ) b ( vec_new [u] )
    ( vec_push [u] b # u 65 )
    ^ @ Resp { st b }
}

@ write Resp r → i { ^ + . r status ( vec_len [u] . r body ) }

@ each ( Vec Resp ) rs ( @ v Resp ) f → v {
    : ~ i k 0
    ~ < k ( vec_len [Resp] rs ) {
        ?? ( vec_get [Resp] rs k ) { T r → { ( f r ) } F → {} }
        = k + k 1
    }
}

// a cursor, replaced by a fresh value inside the closure
@ fresh_into_cursor i rounds → i {
    : ~ Resp dflt ( mk 500 )
    : ~ i acc 0
    : ~ i k 0
    ~ < k rounds {
        : ~ Resp resp dflt
        : ( @ v ) f \ → v { = resp ( mk 200 ) }
        ? != k 3 { ( f ) } {}
        = acc + acc ( write resp )
        = k + k 1
    }
    ^ acc
}

// an owner, replaced twice by fresh values
@ fresh_into_owner → i {
    : ~ Resp resp ( mk 1 )
    : ( @ v ) f \ → v { = resp ( mk 2 ) }
    ( f )
    ( f )
    ^ ( write resp )
}

// borrowed elements assigned over the binding: they stay the Vec's
@ borrowed_elements ( Vec Resp ) rs → i {
    : ~ Resp best ( mk 0 )
    ( each rs \ Resp r → v { ? > . r status . best status { = best r } {} } )
    ^ . best status
}

@ main → i {
    : ( Vec Resp ) rs ( vec_new [Resp] )
    ( vec_push [Resp] rs ( mk 3 ) ) ( vec_push [Resp] rs ( mk 9 ) ) ( vec_push [Resp] rs ( mk 4 ) )
    : i l0 ( live )
    : ~ i acc 0
    : ~ i k 0
    ~ < k 5 {
        = acc + + + acc ( fresh_into_cursor 10 ) ( fresh_into_owner ) ( borrowed_elements rs )
        = k + k 1
    }
    ( nurl_print_int acc ) ( nurl_print `\n` )
    ( nurl_print `live: ` ) ( nurl_print_int - ( live ) l0 ) ( nurl_print `\n` )
    ^ 0
}

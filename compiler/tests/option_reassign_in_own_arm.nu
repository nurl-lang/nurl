// option_reassign_in_own_arm.nu — reassigning an option binding inside the
// `??` arm that matched it drops the value it held, or hands it to the
// payload cursor when that is still used.
//
// `?? cur { T c → { = cur ( next ) } }`: the drop of the old value looked for
// a drop of the option's value type `{ i1, T }` instead of the binding's
// registered twin `%__opt.T`, found none, and emitted nothing — every
// iteration leaked the old value (the pooled keep-alive client loop). The
// cursor `c` over it keeps it alive when read after the assignment.

$ `stdlib/core/vec.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe @ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

: Box2 { ( Vec u ) data }

@ mk i n → Box2 {
    : ( Vec u ) d ( vec_new [u] )
    : ~ i k 0
    ~ < k n { ( vec_push [u] d # u k ) = k + k 1 }
    ^ @ Box2 { d }
}

@ len_of Box2 b → i { ^ ( vec_len [u] . b data ) }

// the old value unused after the assignment
@ unused → i {
    : ~ ? Box2 cur @ ?Box2 { T ( mk 1 ) }
    : ~ i k 0
    ~ < k 3 {
        ?? cur { T c → { = cur @ ?Box2 { T ( mk + k 2 ) } } F _ → {} }
        = k + k 1
    }
    ^ ?? cur { T c → ( len_of c ) F _ → 0 }
}

// the cursor read after the assignment
@ read_after → i {
    : ~ ? Box2 cur @ ?Box2 { T ( mk 1 ) }
    : ~ i k 0
    : ~ i acc 0
    ~ < k 3 {
        ?? cur { T c → { = cur @ ?Box2 { T ( mk + k 2 ) } = acc + acc ( len_of c ) } F _ → {} }
        = k + k 1
    }
    ^ acc
}

@ main → i {
    : i l0 ( live )
    : ~ i acc 0
    : ~ i k 0
    ~ < k 5 { = acc + + acc ( unused ) ( read_after ) = k + k 1 }
    ( nurl_print_int acc ) ( nurl_print `\n` )
    ( nurl_print `live: ` ) ( nurl_print_int - ( live ) l0 ) ( nurl_print `\n` )
    ^ 0
}

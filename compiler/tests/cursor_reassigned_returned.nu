// cursor_reassigned_returned.nu — a cursor reassigned on one path takes its
// source's value along only on the path where it still holds it.
//
// `: ~ ( Vec u ) sk body … ? re { = sk ( mk 50 ) } {} … ^ @ R { 1 sk }`:
// returning the cursor cleared `body`'s flag on every path, so where `sk`
// held a new value `body`'s own leaked (stdlib pkey's PKCS#8 unwrap).

$ `stdlib/core/vec.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe

@ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

: R { i level ( Vec u ) sk }

@ mk i n → ( Vec u ) {
    : ( Vec u ) v ( vec_new [u] )
    : ~ i k 0
    ~ < k n { ( vec_push [u] v # u k ) = k + k 1 }
    ^ v
}

@ f b re → R {
    : ( Vec u ) body ( mk 10 )
    : ~ ( Vec u ) sk body
    ? re { = sk ( mk 5 ) } {}
    ^ @ R { 1 sk }
}

@ main → i {
    : i l0 ( live )
    : ~ i acc 0
    : ~ i k 0
    ~ < k 10 {
        : R a ( f == % k 2 0 )
        = acc + acc ( vec_len [u] . a sk )
        = k + k 1
    }
    ( nurl_print_int acc ) ( nurl_print `\n` )
    ( nurl_print `live: ` ) ( nurl_print_int - ( live ) l0 ) ( nurl_print `\n` )
    ^ 0
}

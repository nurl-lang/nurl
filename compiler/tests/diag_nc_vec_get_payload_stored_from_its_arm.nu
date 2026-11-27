// diag_nc_vec_get_payload_stored_from_its_arm.nu — a `vec_get` payload that
// cannot be copied (a struct holding a trait object), handed from its `??`
// arm to a callee that keeps it. Taking it out of its slot would leave zero
// bytes in the Vec, which are no trait object: a later method call through
// that element called a null vtable. Refused at module end, as a store of
// what a call lends: take the element out of the Vec (vec_remove, vec_pop).
$ `stdlib/core/vec.nu`

% Speaker [T] { @ speak T self → i }

: Dog { i pitch }

% Speaker Dog { @ speak Dog d → i { ^ . d pitch } }

: Pet { % Speaker s }

@ mk i k → Pet { ^ @ Pet { ( dyn Speaker @ Dog { k } ) } }

@ sum ( Vec Pet ) vs → i {
    : ~ i t 0
    ~ x vs { = t + t ( speak . x s ) }
    ^ t
}

@ main → i {
    : ( Vec Pet ) vs ( vec_new [Pet] )
    ( vec_push [Pet] vs ( mk 4 ) )
    : ( Vec Pet ) ws ( vec_new [Pet] )
    ?? ( vec_get [Pet] vs 0 ) { T p → { ( vec_push [Pet] ws p ) } F → {} }
    ( nurl_println_int ( sum ws ) )
    ( nurl_println_int ( sum vs ) )
    ^ 0
}

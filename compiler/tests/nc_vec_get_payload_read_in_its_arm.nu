// nc_vec_get_payload_read_in_its_arm.nu — a `vec_get` payload that cannot
// be copied, handed from its `??` arm to a function that only reads it:
// nothing is taken out of the Vec, which still holds the element, and both
// read it. Runs clean under AddressSanitizer.
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

@ look Pet p → i { ^ ( speak . p s ) }

@ main → i {
    : ( Vec Pet ) vs ( vec_new [Pet] )
    ( vec_push [Pet] vs ( mk 4 ) )
    : ( Vec Pet ) ws ( vec_new [Pet] )
    ?? ( vec_get [Pet] vs 0 ) { T p → { ( nurl_println_int ( look p ) ) } F → {} }
    ( nurl_println_int ( sum ws ) )
    ( nurl_println_int ( sum vs ) )
    ^ 0
}

// diag_nc_vec_get_payload_stored_by_a_forwarder.nu — as
// diag_nc_vec_get_payload_stored_from_its_arm, through a function of the
// program's that keeps it, defined below the call: decided on its final
// summary.
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
    ?? ( vec_get [Pet] vs 0 ) { T p → { ( keep ws p ) } F → {} }
    ( nurl_println_int ( sum ws ) )
    ( nurl_println_int ( sum vs ) )
    ^ 0
}

@ keep ( Vec Pet ) w Pet p → v { ( vec_push [Pet] w p ) }

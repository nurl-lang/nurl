// diag_nc_field_option_payload_stored_from_its_arm.nu — a payload that
// cannot be copied, of an option in a struct's field, stored into a Vec from
// its arm: the struct still drops the option, so the arm only borrows the
// payload. Refused; before, the Vec and the struct both released it. (Read
// in the arm, it stays accepted: nc_payload_moved_out_of_its_option.)
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

: Holder { ? Pet o }

@ main → i {
    : ( Vec Pet ) vs ( vec_new [Pet] )
    : Holder h @ Holder { @ ?Pet { T ( mk 3 ) } }
    ?? . h o { T p → { ( vec_push [Pet] vs p ) } F → {} }
    ( nurl_println_int ( sum vs ) )
    ^ 0
}

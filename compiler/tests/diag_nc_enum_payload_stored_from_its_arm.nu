// diag_nc_enum_payload_stored_from_its_arm.nu — an enum's payload that
// cannot be copied (Pet holds a trait object), stored into a Vec from its
// arm: the enum keeps it in its own cell, so the arm only borrows it (h231),
// and there is no copy to hand over. Refused; before, it was handed over as
// it was, and released by the Vec and by the enum.
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

: | Zoo { Nada One Pet }

@ main → i {
    : ( Vec Pet ) vs ( vec_new [Pet] )
    : Zoo z @ Zoo { One ( mk 2 ) }
    ?? z { One p → { ( vec_push [Pet] vs p ) } Nada → {} }
    ( nurl_println_int ( sum vs ) )
    ^ 0
}

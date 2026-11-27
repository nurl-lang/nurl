// diag_nc_option_read_after_its_payload_moved.nu — an option whose payload
// cannot be copied, matched again after its payload was moved into a Vec:
// the second match reads what the Vec owns now. Refused, as for a String
// payload; before, it compiled, and the option released the payload again.
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
    : ?Pet got @ ?Pet { T ( mk 3 ) }
    ?? got { T p → { ( vec_push [Pet] vs p ) } F → {} }
    : i n ?? got { T q → ( speak . q s ) F → 0 }
    ( nurl_println_int n )
    ^ 0
}

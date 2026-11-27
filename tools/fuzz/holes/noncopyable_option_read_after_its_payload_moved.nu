// noncopyable_option_read_after_its_payload_moved: an option binding matched again after its non-copyable payload was moved into a Vec — the second match read what the Vec owned, and the option released it at its end.
// Closed: the payload is a cursor over the option, so the walk sees the option consumed by the move.
// main: accepted; AddressSanitizer reported a bad free.
// map: §7.6 | A2 | rejected | - | an option read after its non-copyable payload moved out of its arm
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

// noncopyable_enum_payload_stored_from_its_arm: an enum's payload that cannot be copied, the enum held by a binding, stored into a Vec from its arm (and, the same, an option in a struct's field) — handed over as it was: the Vec and the enum both released it.
// Closed: it is lent to the arm, as a `% Drop` payload is (h231); a store would need a copy, which cannot be made, and is refused.
// main: accepted; AddressSanitizer reported a bad free.
// map: §7.6 | A2 | rejected | h231 | a non-copyable enum payload stored from its arm: the enum released it again
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

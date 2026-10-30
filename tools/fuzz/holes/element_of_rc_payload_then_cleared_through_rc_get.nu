// element_of_rc_payload_then_cleared_through_rc_get: agora #169 — a mutator called on a value an accessor lends (element_of_rc_payload_then_cleared_through_rc_get).
// Closed: the call changes what the accessor lends from (agora #169).
// v0.80.0: accepted; AddressSanitizer reported a fault.
// map: §2.11 | A2 | rejected | h588 | agora #169: element_of_rc_payload_then_cleared_through_rc_get
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

@ main → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( mk ) )
    : ( Rc ( Vec String ) ) r ( rc_new [( Vec String )] v )
    : String e ( vec_at [String] ( rc_get [( Vec String )] r ) 0 )
    ( vec_clear [String] ( rc_get [( Vec String )] r ) )
    ( nurl_println ( string_data e ) )
    ^ 0
}

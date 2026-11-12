// rc_in_the_payload_of_an_rc_cleared_through_a_lent_payload_past_a_view_through_another_share: `: Impl { ( Vec String ) items ( Rc ( Vec String ) ) side }` in an Rc; `( vec_clear ( rc_get . ca side ) )` with `ca` lent out of `. h a`, while an element is read through `rs2`, another share of the inner Rc
// Closed: an Rc's reach includes the Rcs held in its payload (agora #592).
// main 3b63ee3b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #592: an Rc in the payload of an Rc cleared through a lent payload, past a view through another share
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

: Impl { ( Vec String ) items ( Rc ( Vec String ) ) side }
: RI { ( Rc Impl ) a }

@ main → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `an element string long enough for a heap buffer` ) )
    : ( Rc ( Vec String ) ) rs ( rc_new [( Vec String )] v )
    : ( Rc ( Vec String ) ) rs2 ( rc_clone [( Vec String )] rs )
    : ~ RI h @ RI { ( rc_new [Impl] @ Impl { ( vec_new [String] ) rs } ) }
    : String e ( vec_at [String] ( rc_get [( Vec String )] rs2 ) 0 )
    : Impl ca ( rc_get [Impl] . h a )
    : ( Vec String ) sv ( rc_get [( Vec String )] . ca side )
    ( vec_clear [String] sv )
    ( nurl_println ( string_data e ) )
    ^ 0
}

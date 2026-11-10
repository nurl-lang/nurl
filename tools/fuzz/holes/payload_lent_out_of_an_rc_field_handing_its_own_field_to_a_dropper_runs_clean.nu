// payload_lent_out_of_an_rc_field_handing_its_own_field_to_a_dropper_runs_clean: `: Impl cl ( rc_get . . call client a )`, `( vec_clear [String] . cl items )`, then `. cl items` read again — gRPC's `% Drop GrpcCall` shape (the shape the fix must keep)
// Closed: a borrow lent out of a share reaches its source through that very share; the same-Rc rule asks other handles only (agora #566).
// main a403b200: runs clean.
// map: §2.12 | A2 | runs-clean | - | agora #566: a payload lent out of an Rc field handing its own field to a dropper, read again
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`

: Impl { ( Vec String ) items i n }
: Client { ( Rc Impl ) a }
: Call { Client client i id }

@ main → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `an element string long enough for a heap buffer` ) )
    : ~ Call call @ Call { @ Client { ( rc_new [Impl] @ Impl { v 1 } ) } 7 }
    : Impl cl ( rc_get [Impl] . . call client a )
    ( vec_clear [String] . cl items )
    ( nurl_println_int ( vec_len [String] . cl items ) )
    ^ 0
}

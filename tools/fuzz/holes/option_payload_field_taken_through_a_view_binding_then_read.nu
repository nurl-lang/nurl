// option_payload_field_taken_through_a_view_binding_then_read: agora #336 — a `??` payload's field read into a binding (`: pl . f payload`) and handed to an outer owner (`= msg pl`) moves out of the option, as `= msg . f payload` does; the option, matched again after msg released it, read the freed buffer.
// Closed: the move through the binding takes the option apart for the borrow checker too (mem_udrop_field_move → mem_udrop_takeover_opt; agora #336).
// main: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #336: a payload's field moved out through a view binding, the option read again after
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Fr { ( Vec u ) payload i op }

@ read_one i k → !Fr i {
    : ~ ( Vec u ) v ( vec_new [u] )
    ( vec_push [u] v 65 ) ( vec_push [u] v 66 )
    ^ @ !Fr i { T @ Fr { v k } }
}

@ main → i {
    : ~ ( Vec u ) msg ( vec_new [u] )
    : !Fr i fr ( read_one 1 )
    ?? fr {
        T f → {
            : ( Vec u ) pl . f payload
            = msg pl
        }
        F e → {}
    }
    = msg ( vec_new [u] )
    ?? fr {
        T g → { : ( Vec u ) gp . g payload ( nurl_println_int # i ( vec_at [u] gp 0 ) ) }
        F e → {}
    }
    ^ 0
}

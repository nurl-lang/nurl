// option_payload_field_taken_through_a_view_binding_in_a_loop: agora #336 — stdlib/ext/websocket.nu's reader: each frame's `??` payload field read into a binding and handed to the message kept past the loop (`= msg_payload pl`). It moves out of the option, so the message owns it (the shape the fix must keep).
// Closed: the move through the binding takes the option apart for the borrow checker (mem_udrop_field_move → mem_udrop_takeover_opt), so the payload is no cursor over it any more when its arm ends (agora #336).
// main: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #336: a payload's field moved out through a view binding to an owner outside the loop
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
    : ~ i n 0
    ~ < n 3 {
        = n + n 1
        : !Fr i fr ( read_one n )
        ?? fr {
            T f → {
                : ( Vec u ) pl . f payload
                ? == n 2 { = msg pl } {}
            }
            F e → {}
        }
    }
    ( nurl_println_int ( vec_len [u] msg ) )
    ^ 0
}

// move_then_reassign_in_loop.nu — a binding one branch inside a loop moves out
// and refills (`= msg acc = acc ( vec_new [u] )`) is still dropped at scope
// exit, whichever branch ran (stdlib websocket's fragmented-message reader).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

: Frame { i op ( Vec u ) payload }
: | Err { E1 E2 }
: Msg { i kind ( Vec u ) data }

@ read_frame i k → !Frame Err {
    ? == k 99 { ^ @ !Frame Err { F E1 } } {}
    : ( Vec u ) p ( vec_new [u] )
    ( vec_push [u] p # u 65 )
    ^ @ !Frame Err { T @ Frame { 1 p } }
}

@ vloop i k → !Msg Err {
    : ~ ( Vec u ) acc ( vec_new [u] )
    : ~ ( Vec u ) msg ( vec_new [u] )
    : ~ b have F
    : ~ b done F
    ~ ! done {
        ?? ( read_frame k ) {
            T frm → {
                : ( Vec u ) pl . frm payload
                ? == . frm op 1 {
                    = msg pl
                    = have T
                    = done T
                } {
                    ( vec_extend [u] acc pl )
                    ? == . frm op 2 {
                        = msg acc
                        = acc ( vec_new [u] )
                        = have T
                        = done T
                    } {}
                }
            }
            F _ → { = done T }
        }
    }
    ? have { ^ @ !Msg Err { T @ Msg { 1 msg } } } { ^ @ !Msg Err { F E2 } }
}

@ main → i {
    : i a0 - ( nurl_alloc_count ) ( nurl_free_count )
    : ~ i k 0
    ~ < k 10 { ?? ( vloop k ) { T m → {} F _ → {} } = k + k 1 }
    : i a1 - ( nurl_alloc_count ) ( nurl_free_count )
    ( nurl_println ( nurl_str_int - a1 a0 ) )
    ^ 0
}

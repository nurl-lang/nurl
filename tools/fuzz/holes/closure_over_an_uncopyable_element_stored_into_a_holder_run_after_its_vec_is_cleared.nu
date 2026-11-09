// closure_over_an_uncopyable_element_stored_into_a_holder_run_after_its_vec_is_cleared: agora #483 — a closure over `e = ( vec_at t 0 )`, a Vec of Drop values, stored into a struct holder's field; `t` cleared; the holder's closure run
// Closed: the closure's copy of the lent value's handle depends on the container's elements, `~^R` (agora #483).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #483: a closure over an uncopyable element stored into a holder, run after its Vec is cleared
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: D { i x }

% Drop D { @ drop D self → v {} }

: H { ( @ i ) cb i pad }

@ main → i {
    : ~ H h @ H { \ → i { ^ 0 } 0 }
    : ~ ( Vec ( Vec D ) ) t ( vec_new [( Vec D )] )
    : ~ ( Vec D ) r ( vec_new [D] )
    ( vec_push [D] r @ D { 1 } )
    ( vec_push [D] r @ D { 2 } )
    ( vec_push [( Vec D )] t r )
    : ( Vec D ) e ( vec_at [( Vec D )] t 0 )
    = . h cb \ → i { ^ ( vec_len [D] e ) }
    ( vec_clear [( Vec D )] t )
    : ( @ i ) g . h cb
    ( nurl_println_int ( g ) )
    ^ 0
}

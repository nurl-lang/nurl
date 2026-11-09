// closure_over_a_payload_of_a_loop_element_run_after_its_owner_is_cleared: agora #483 — `~ o b` over `b = ( vec_at vv 0 )`, a row of `?String`; `?? o` in place, `y` its payload; `f` a closure over `y`; `vv` cleared through a cursor; `f` run after
// Closed: a `??` payload read in place out of a loop element borrows it, as one out of a `vec_at` binding does, so it ends with the container's owners (agora #482).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #483: a closure over a payload of a loop element run after its owner is cleared
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec ( Vec ? String ) ) vv ( vec_new [( Vec ? String )] )
    : ~ ( Vec ? String ) t ( vec_new [? String] )
    ( vec_push [? String] t @ ?String { T ( string_from `a payload long enough for a heap buffer here` ) } )
    ( vec_push [( Vec ? String )] vv t )
    : ~ ( Vec ( Vec ? String ) ) cur vv
    : ( Vec ? String ) b ( vec_at [( Vec ? String )] vv 0 )
    ~ o b {
        ?? o {
            T y → {
                : ( @ i ) f \ → i { ^ ( strlen ( string_data y ) ) }
                ( vec_clear [( Vec ? String )] cur )
                ( nurl_println_int ( f ) )
            }
            F → {}
        }
        break
    }
    ^ 0
}

// loop_over_a_vec_get_payload_read_after_its_owner_is_cleared: agora #482 — `~ x r` over `r`, the payload of `( vec_get vv 0 )`; `vv` cleared in the body; `x` read after
// Closed: the loop's element is a copy of the handle in an element of what the loop iterates; what ends a borrow of an element of its owners ends it, by any route (`feo_`, agora #482).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #482: a loop over a vec_get payload, its owner cleared in the body
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
    : ~ ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    ( vec_push [( Vec String )] vv t )
    ?? ( vec_get [( Vec String )] vv 0 ) {
        T r → {
            ~ x r {
                ( vec_clear [( Vec String )] vv )
                ( nurl_println ( string_data x ) )
            }
        }
        F → {}
    }
    ^ 0
}

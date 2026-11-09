// loop_over_a_borrowed_row_read_after_its_owner_is_sunk: agora #482 — `~ x b` over `b = ( vec_at vv 0 )`; `vv` handed to a `sink` in the body, `x` read after, then `break`
// Closed: the loop's element is a copy of the handle in an element of what the loop iterates; what ends a borrow of an element of its owners ends it, by any route (`feo_`, agora #482).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #482: a loop over a borrowed row, its owner handed to a sink in the body
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ eat sink ( Vec ( Vec String ) ) v → i { ^ ( vec_len [( Vec String )] v ) }

@ main → i {
    : ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
    : ~ ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    ( vec_push [( Vec String )] vv t )
    : ( Vec String ) b ( vec_at [( Vec String )] vv 0 )
    ~ x b {
        ( nurl_println_int ( eat vv ) )
        ( nurl_println ( string_data x ) )
        break
    }
    ^ 0
}

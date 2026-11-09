// loop_over_a_field_read_after_a_helper_drops_a_lent_value_of_it: agora #482 — `~ x . h items`; `( wipe ( items_of h ) )`; `x` read after
// Closed: a row handing a call a value lent out of what a loop element is a part of reaches the borrow sweep, which ends the element (agora #482).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #482: a loop over a field read after a helper drops a lent value of it
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { ( Vec String ) items i n }

@ items_of H q → ( Vec String ) { ^ . q items }

@ wipe ( Vec String ) v → v { ( vec_clear [String] v ) }

@ main → i {
    : ~ H h @ H { ( vec_new [String] ) 0 }
    ( vec_push [String] . h items ( string_from `a string long enough for a heap buffer here` ) )
    ~ x . h items {
        ( wipe ( items_of h ) )
        ( nurl_println ( string_data x ) )
        break
    }
    ^ 0
}

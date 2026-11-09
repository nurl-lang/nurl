// loop_over_a_field_read_after_a_lending_helper_hands_it_to_a_clear: agora #482 — `~ x . h items`; `( vec_clear ( items_of h ) )` in the body, `items_of` handing back `. h items`; `x` read after
// Closed: a row handing a call a value lent out of what a loop element is a part of reaches the borrow sweep, which ends the element (agora #482).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #482: a loop over a field read after a lending helper hands it to a clear
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { ( Vec String ) items i n }

@ items_of H q → ( Vec String ) { ^ . q items }

@ main → i {
    : ~ H h @ H { ( vec_new [String] ) 0 }
    ( vec_push [String] . h items ( string_from `a string long enough for a heap buffer here` ) )
    ~ x . h items {
        ( vec_clear [String] ( items_of h ) )
        ( nurl_println ( string_data x ) )
        break
    }
    ^ 0
}

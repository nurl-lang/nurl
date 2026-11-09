// loop_over_a_field_only_reading_a_lent_value_of_it_runs_clean: agora #482 — `~ x . h items`; `( vec_len ( items_of h ) )` only read; `x` read after; the loop goes on
// The shape the fix must keep: a lent value only read changes nothing (agora #482).
// main 21a0fb5: runs clean.
// map: §2.5 | A2 | runs-clean | - | agora #482: a loop over a field only reading a lent value of it
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { ( Vec String ) items i n }

@ items_of H q → ( Vec String ) { ^ . q items }

@ main → i {
    : ~ H h @ H { ( vec_new [String] ) 0 }
    ( vec_push [String] . h items ( string_from `a string long enough for a heap buffer here` ) )
    ( vec_push [String] . h items ( string_from `a second string long enough for a heap buffer` ) )
    ~ x . h items {
        ( nurl_println_int ( vec_len [String] ( items_of h ) ) )
        ( nurl_println ( string_data x ) )
    }
    ^ 0
}

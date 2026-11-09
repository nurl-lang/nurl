// loop_over_a_row_of_a_struct_field_read_after_a_helper_clears_the_field: agora #482 — `~ x b` over `b = ( vec_at . h rows 0 )`; a helper handed `. h rows` clears it in the body; `x` read after
// Closed: the loop's element is a copy of the handle in an element of what the loop iterates; what ends a borrow of an element of its owners ends it, by any route (`feo_`, agora #482).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #482: a loop over a row of a struct field read after a helper clears the field
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { ( Vec ( Vec String ) ) rows i n }

@ wipe ( Vec ( Vec String ) ) v → v { ( vec_clear [( Vec String )] v ) }

@ main → i {
    : H h @ H { ( vec_new [( Vec String )] ) 0 }
    : ~ ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    ( vec_push [( Vec String )] . h rows t )
    : ( Vec String ) b ( vec_at [( Vec String )] . h rows 0 )
    ~ x b {
        ( wipe . h rows )
        ( nurl_println ( string_data x ) )
        break
    }
    ^ 0
}

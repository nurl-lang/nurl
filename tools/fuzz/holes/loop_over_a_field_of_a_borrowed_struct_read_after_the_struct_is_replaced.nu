// loop_over_a_field_of_a_borrowed_struct_read_after_the_struct_is_replaced: agora #482 — `~ x . b items` over `b = ( vec_at bs 0 )`, a struct; the row replaced by `vec_set` in the body; `x` read after
// Closed: the loop's element is a copy of the handle in an element of what the loop iterates; what ends a borrow of an element of its owners ends it, by any route (`feo_`, agora #482).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #482: a loop over a field of a borrowed struct, the struct replaced in the body
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: B { ( Vec String ) items i n }

@ main → i {
    : ( Vec B ) bs ( vec_new [B] )
    : B b0 @ B { ( vec_new [String] ) 0 }
    ( vec_push [String] . b0 items ( string_from `a string long enough for a heap buffer here` ) )
    ( vec_push [B] bs b0 )
    : B b ( vec_at [B] bs 0 )
    ~ x . b items {
        ( vec_set [B] bs 0 @ B { ( vec_new [String] ) 1 } )
        ( nurl_println ( string_data x ) )
    }
    ^ 0
}

// view_of_a_matched_payload_field_past_a_callee_growing_it: a slice of `. q v`, q a struct payload cursor, the option handed to a callee growing that field
// Closed: a callee growing the option's payload ends the views of a payload cursor over it, of a cursor over that cursor, and of the cursor's field paths; one moving only an element's buffer ends only the views through the elements (agora #816's review).
// main 83059aae: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #816: a view of a matched payload's field past a callee growing it
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/core/box.nu`

: P { ( Vec u ) v i n }

@ w ? P o → v {
    ?? o { T p → ( vec_reserve [u] . p v 4096 ) F → {} }
}

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ?P o @ ?P { T @ P { xs 0 } }
    ?? o {
        T q → {
            : ( Slice u ) sl ( slice_from_vec [u] . q v )
            ( w o )
            ( nurl_println_int # i ( slice_at [u] sl 0 ) )
        }
        F → {}
    }
    ^ 0
}

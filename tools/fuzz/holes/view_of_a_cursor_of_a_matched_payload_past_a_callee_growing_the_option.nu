// view_of_a_cursor_of_a_matched_payload_past_a_callee_growing_the_option: a payload cursor of a payload cursor, a slice of the inner one, the outer option handed to a grower
// Closed: a callee growing the option's payload ends the views of a payload cursor over it, of a cursor over that cursor, and of the cursor's field paths; one moving only an element's buffer ends only the views through the elements (agora #816's review).
// main 83059aae: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #816: a view of a cursor of a matched payload past a callee growing the option
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/core/box.nu`

@ w2 ?? ( Vec u ) oo → v {
    ?? oo { T o2 → ?? o2 { T p → ( vec_reserve [u] p 4096 ) F → {} } F → {} }
}

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ?( Vec u ) o @ ?( Vec u ) { T xs }
    : ?? ( Vec u ) oo @ ?? ( Vec u ) { T o }
    ?? oo {
        T o2 → {
            ?? o2 {
                T q → {
                    : ( Slice u ) sl ( slice_from_vec [u] q )
                    ( w2 oo )
                    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
                }
                F → {}
            }
        }
        F → {}
    }
    ^ 0
}

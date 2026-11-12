// struct_field_bound_then_looped_over_and_grown_by_a_callee: the callee binding `: rs . p rows` and looping over it
// Closed: a callee that may move the buffer of an element of what it is handed (g_fn_ireallocs), handed a struct whole, ends the views through elements of the struct's field paths too — `( vec_at . w rows 0 )` is an element of `w.rows`, the source the view was taken of (agora #785).
// main ad17e78c: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #785: a struct field bound, looped over and grown by a callee
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/hashmap.nu`
$ `stdlib/std/deque.nu`

: P { ( Vec ( Vec u ) ) rows }

@ top P p → v { : ( Vec ( Vec u ) ) rs . p rows ~ e rs { ( vec_reserve [u] e 4096 ) } }

@ main → i {
    : ( Vec ( Vec u ) ) w ( vec_new [( Vec u )] )
    : ( Vec u ) a ( vec_new [u] )
    ( vec_push [u] a 7 )
    ( vec_push [( Vec u )] w a )
    : P p @ P { w }
    : ( Slice u ) sl ( slice_from_vec [u] ( vec_at [( Vec u )] . p rows 0 ) )
    ( top p )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

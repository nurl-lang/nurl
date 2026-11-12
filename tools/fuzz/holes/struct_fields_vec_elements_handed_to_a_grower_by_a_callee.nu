// struct_fields_vec_elements_handed_to_a_grower_by_a_callee: the callee handing each element of `. p rows` to a helper that grows it
// Closed: a callee that may move the buffer of an element of what it is handed (g_fn_ireallocs), handed a struct whole, ends the views through elements of the struct's field paths too — `( vec_at . w rows 0 )` is an element of `w.rows`, the source the view was taken of (agora #785).
// main ad17e78c: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #785: a struct field's Vec elements handed to a grower by a callee
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/hashmap.nu`
$ `stdlib/std/deque.nu`

: P { ( Vec ( Vec u ) ) rows }

@ grow ( Vec u ) x → v { ( vec_reserve [u] x 4096 ) }

@ top P p → v { ~ e . p rows { ( grow e ) } }

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

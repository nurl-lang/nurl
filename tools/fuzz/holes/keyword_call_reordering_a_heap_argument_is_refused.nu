// keyword_call_reordering_a_heap_argument_is_refused: `( clr2 n: 0 v: v )`: a heap-holding binding passed by name out of the declared order.
// Closed: the reordering path keeps no borrow rows, so such an argument is refused there with advice (agora #434).
// main 74a4a4eb: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #434: `( clr2 n: 0 v: v )`: a heap-holding binding passed by name out of the declared order
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ clr2 ( Vec String ) v i n = 0 → v { ? == n 0 { ( vec_clear [String] v ) } {} }

@ main → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `an element string, long enough for the heap` ) )
    : String e ( vec_at [String] v 0 )
    ( clr2 n : 0 v : v )
    ( nurl_println ( string_data e ) )
    ^ 0
}

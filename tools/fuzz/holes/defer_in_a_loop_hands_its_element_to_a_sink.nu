// defer_in_a_loop_hands_its_element_to_a_sink: a `;` defer in a `~ e v` body hands `e` to a `sink` parameter; it runs at the exit, and v releases the element again.
// Closed: in a defer body the element is no slot of its loop (__fe_has_slot) but a borrow of its container to the walk, and a borrow is not handed over (agora #672).
// main ae5e524: accepted; AddressSanitizer: heap-use-after-free (nested in another loop: invalid IR).
// map: §2.1 | A2 | rejected | - | agora #672: a defer in a ~ loop body hands the element to a sink
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk s p i k → String { : ~ String r ( string_from p ) ( string_push_int r k ) ^ r }

@ mg i k → String { ^ ( mk `g: a loop string long enough for a heap buffer ` k ) }

@ eat sink String x → i { ^ ( string_len x ) }

: S { String name i n }

@ eats sink S s → i { ^ . s n }

@ f i n → i {
    : ~ ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( mg 0 ) ) ( vec_push [String] v ( mg 1 ) )
    ~ e v { ; { ( nurl_println_int ( eat e ) ) } }
    ^ n
}

@ main → i { ( nurl_println_int ( f 1 ) ) ^ 0 }

// defer_in_a_loop_hands_a_field_of_its_element_to_a_sink: a `;` defer in a `~ e v` body hands `. e name` to a `sink` parameter; the container still holds that field and releases it again.
// Closed: the field is no slot's there: a `pendfx` row, refused as a `vec_at` copy's field handed to a taker is (agora #672).
// main ae5e524: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.12 | A2 | rejected | - | agora #672: a defer in a ~ loop body hands a field of the element to a sink
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk s p i k → String { : ~ String r ( string_from p ) ( string_push_int r k ) ^ r }

@ mg i k → String { ^ ( mk `g: a loop string long enough for a heap buffer ` k ) }

@ eat sink String x → i { ^ ( string_len x ) }

: S { String name i n }

@ eats sink S s → i { ^ . s n }

@ f i n → i {
    : ~ ( Vec S ) v ( vec_new [S] )
    ( vec_push [S] v @ S { ( mg 0 ) 1 } )
    ~ e v { ; { ( nurl_println_int ( eat . e name ) ) } }
    ^ n
}

@ main → i { ( nurl_println_int ( f 1 ) ) ^ 0 }

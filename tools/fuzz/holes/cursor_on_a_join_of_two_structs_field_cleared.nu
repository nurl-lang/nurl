// cursor_on_a_join_of_two_structs_field_cleared: `: ~ H hc ? flag g h`, two struct owners, then `( vec_clear [String] . hc items )` (flag false: `. h items`) while `e`, an element of `. h items`, is still read.
// Closed: a `: ~` cursor on a join of names makes no alias rows; its borrow begins from each arm, the source expression its row carries, so a clear of a field through it ends the borrows of that field of either owner (agora #498).
// main b997834: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A1 | rejected | - | agora #498: a `: ~` cursor on a join of two struct owners, a field cleared through it under an element borrow
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { ( Vec String ) items i k }

@ main → i {
    : ~ H h @ H { ( vec_new [String] ) 0 }
    : ~ H g @ H { ( vec_new [String] ) 1 }
    ( vec_push [String] . h items ( string_from `an element string long enough for a heap buffer` ) )
    : b flag == ( vec_len [String] . g items ) 1
    : String e ( vec_at [String] . h items 0 )
    : ~ H hc ? flag g h
    ( vec_clear [String] . hc items )
    ( nurl_println ( string_data e ) )
    ^ 0
}

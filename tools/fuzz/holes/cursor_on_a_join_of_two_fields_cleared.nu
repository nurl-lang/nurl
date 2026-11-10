// cursor_on_a_join_of_two_fields_cleared: `: ~ ( Vec Nd ) c ? own . u kids . t kids`, then `( vec_clear [Nd] c )` (own false: it clears `. t kids`) while `e`, an element of `. t kids`, is still read.
// Closed: the cursor's borrow begins from each arm's field path, the source expression its row carries (agora #498).
// main b997834: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A1 | rejected | - | agora #498: a `: ~` cursor on a join of two field paths cleared under an element borrow of one arm
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Nd { ( Vec Nd ) kids String name }

@ mk String s → Nd { ^ @ Nd { ( vec_new [Nd] ) s } }

@ main → i {
    : ~ Nd t ( mk ( string_from `t` ) )
    : ~ Nd u ( mk ( string_from `u` ) )
    ( vec_push [Nd] . t kids ( mk ( string_from `a child name long enough for the heap` ) ) )
    : b own == ( vec_len [Nd] . u kids ) 1
    : Nd e ( vec_at [Nd] . t kids 0 )
    : ~ ( Vec Nd ) c ? own . u kids . t kids
    ( vec_clear [Nd] c )
    ( nurl_println ( string_data . e name ) )
    ^ 0
}

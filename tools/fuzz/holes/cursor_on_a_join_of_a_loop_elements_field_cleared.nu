// cursor_on_a_join_of_a_loop_elements_field_cleared: in `~ x rs`, `: ~ ( Vec String ) c ? own o . x f`, then `( vec_clear [String] c )` (own false: `. x f`) while `e`, an element of `. x f`, is still read.
// Closed: the cursor's borrow begins from each arm — the owner `o` and the loop element's field `. x f` — the source expression its row carries (agora #498).
// main b997834: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #498: a `: ~` cursor on a join of an owner and a loop element's field, cleared under an element borrow
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: R { ( Vec String ) f i k }

@ main → i {
    : ( Vec R ) rs ( vec_new [R] )
    : ( Vec String ) inner ( vec_new [String] )
    ( vec_push [String] inner ( string_from `an element string long enough for a heap buffer` ) )
    ( vec_push [R] rs @ R { inner 0 } )
    : ~ ( Vec String ) o ( vec_new [String] )
    : b own == ( vec_len [String] o ) 1
    ~ x rs {
        : String e ( vec_at [String] . x f 0 )
        : ~ ( Vec String ) c ? own o . x f
        ( vec_clear [String] c )
        ( nurl_println ( string_data e ) )
    }
    ^ 0
}

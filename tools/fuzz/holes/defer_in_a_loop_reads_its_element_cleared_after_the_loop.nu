// defer_in_a_loop_reads_its_element_cleared_after_the_loop: a `;` defer in a `~ e v` body reads the element `e`; the Vec is cleared after the loop, before the defer runs at the function's exit.
// Closed: an element a defer of its loop's body reads is a borrow of the container from the loop's end on, as `: String e ( vec_at v 0 )` is: the clear ends it and the defer's read is refused, as that binding's is (agora #672).
// main 3c4322c: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #672: a defer in a ~ loop body reads the element; the Vec is cleared after the loop
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk s p i k → String { : ~ String r ( string_from p ) ( string_push_int r k ) ^ r }

@ mg i k → String { ^ ( mk `g: a loop string long enough for a heap buffer ` k ) }

@ pr String g → v { ( nurl_println ( string_data g ) ) }

@ f i n → i {
    : ~ ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( mg 0 ) ) ( vec_push [String] v ( mg 1 ) )
    ~ e v {
        ; { ( pr e ) }
    }
    ( vec_clear [String] v )
    ^ n
}

@ main → i { ( nurl_println_int ( f 1 ) ) ^ 0 }

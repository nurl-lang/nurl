// borrow_defer_in_a_loop_reads_its_element_cleared_after.nu — a `;` defer
// in a `~ e v` body reads the element `e`, and runs at the function's exit:
// after the loop, past the `( vec_clear … v )` that dropped every element.
// The element lives, as a borrow of `v`, from the loop's end to the exit —
// as `: String e ( vec_at [String] v 0 )` would — so the clear ends it and
// the defer's read is refused, with a note that says when the defer runs
// (Agora #672). Before, it read the freed String.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ pr String g → v { ( nurl_println ( string_data g ) ) }

@ f i n → i {
    : ~ ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `first element, long enough for the heap` ) )
    ( vec_push [String] v ( string_from `second element, long enough for the heap` ) )
    ~ e v {
        ; { ( pr e ) }
    }
    ( vec_clear [String] v )
    ^ n
}

@ main → i { ^ ( f 0 ) }

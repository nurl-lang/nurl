// defer_in_a_nested_loop_reads_its_element_cleared_after_the_outer_loop: a `;` defer in an inner `~ e v` body, inside a counting loop, reads the element; the Vec is cleared after the outer loop.
// Closed: the outer loop keeps the inner loop's element a defer reads, with what it borrows, across its back-edge and exit, as it keeps a `:` binding of its body (agora #672, #670).
// main 3c4322c: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #672: a defer in a ~ loop nested in a counting loop reads the element; the Vec is cleared after the outer loop
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk s p i k → String { : ~ String r ( string_from p ) ( string_push_int r k ) ^ r }

@ mg i k → String { ^ ( mk `g: a loop string long enough for a heap buffer ` k ) }

@ pr String g → v { ( nurl_println ( string_data g ) ) }

@ f i n → i {
    : ~ ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( mg 0 ) ) ( vec_push [String] v ( mg 1 ) )
    : ~ i k 0
    ~ < k n {
        ~ e v {
            ; { ( pr e ) }
        }
        = k + k 1
    }
    ( vec_clear [String] v )
    ^ k
}

@ main → i { ( nurl_println_int ( f 2 ) ) ^ 0 }

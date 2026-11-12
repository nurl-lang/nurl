// defer_in_a_loop_reads_its_element_of_an_unchanged_vec_runs_clean: a `;` defer in a `~ e v` body, nested in a counting loop, reads the element; the Vec is grown after the loop and never cleared.
// Control for agora #672: keeping the element to the exit refuses no program that leaves the elements alone; the defer prints the last element the loop saw.
// map: §2.10 | A2 | runs-clean | - | agora #672: a defer in a nested ~ loop reads the element of a Vec only grown after the loop
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk s p i k → String { : ~ String r ( string_from p ) ( string_push_int r k ) ^ r }

@ mg i k → String { ^ ( mk `g: a loop string long enough for a heap buffer ` k ) }

@ pr String g → v { ( nurl_println ( string_data g ) ) }

@ f ( Vec String ) v i n → i {
    : ~ i k 0
    ~ < k n {
        ~ e v {
            ; { ( pr e ) }
        }
        = k + k 1
    }
    ^ k
}

@ main → i {
    : ~ ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( mg 0 ) ) ( vec_push [String] v ( mg 1 ) )
    ( nurl_println_int ( f v 2 ) )
    ( vec_push [String] v ( mg 2 ) )
    ^ 0
}

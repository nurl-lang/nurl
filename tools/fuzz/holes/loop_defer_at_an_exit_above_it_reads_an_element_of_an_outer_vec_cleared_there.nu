// loop_defer_at_an_exit_above_it_reads_an_element_of_an_outer_vec_cleared_there: `: ~ ( Vec String ) w …  ~ c { ( vec_clear w ) ( vec_push w … )  ? d { ^ 1 } {}  : String e ( vec_at w 0 )  ; { … e … } }`.
// Closed: rejected. A `^` above a loop body's `;` runs that defer from the second round on (an earlier round armed it, agora #670); there `e` still holds the earlier round's element, which this round's `vec_clear` dropped.
// main 0b3f239: accepted; it ran clean only because the `^` skipped the defer (#670's wrong output). With the defer run there and the walk unchanged: AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #670: a `^` above a loop body's `;` runs the defer with an earlier round's element of an outer Vec this round cleared
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk i k → String { : ~ String r ( string_from `w: an element long enough for a heap buffer ` ) ( string_push_int r k ) ^ r }

@ f i d → i {
    : ~ ( Vec String ) w ( vec_new [String] )
    : ~ i k 0
    ~ < k 3 {
        ( vec_clear [String] w )
        ( vec_push [String] w ( mk k ) )
        ? == k d { ^ 1 } {}
        : String e ( vec_at [String] w 0 )
        ; { ( nurl_println ( string_data e ) ) }
        = k + k 1
    }
    ^ 0
}

@ main → i {
    ( nurl_println_int ( f 1 ) )
    ^ 0
}

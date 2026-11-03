// cursor_over_views_ended_with_an_empty_literal_runs_clean: a loop walks a cursor over two Strings' views and ends it with the empty literal (`= rest ```); the piece copied at the top of a round is read after the cursor moves on. Nothing is ever owned by the cursor.
// Kept: only a view binding that the walk has seen given a value that may be its own (a row marked `o`, an `@assign`) may own its value where paths meet (bck_may_own_some); one given only views and literals owns nothing, and re-pointing it frees nothing.
// main 4f15689: accepted; ran clean.
// map: StmtT.assign | A1 | runs-clean | - | a loop cursor given only views and the empty literal: a copy outlives a re-point
$ `stdlib/core/string.nu`

@ walk String a String b → i {
    : ~ s rest ( string_data a )
    : ~ i n 0
    : ~ i k 0
    ~ != 0 ( nurl_str_len rest ) {
        : s piece rest
        ? == k 0 { = rest ( string_data b ) } { = rest `` }
        = n + n ( nurl_str_len piece )
        = k + k 1
    }
    ^ n
}

@ main → i {
    : String a ( string_from `abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJ` )
    : String b ( string_from `another string long enough for the heap buffer` )
    ( nurl_print_int ( walk a b ) ) ( nurl_print `\n` )
    ^ 0
}

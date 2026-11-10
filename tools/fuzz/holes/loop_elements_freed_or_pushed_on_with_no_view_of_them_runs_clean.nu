// loop_elements_freed_or_pushed_on_with_no_view_of_them_runs_clean: agora #490 — a loop that frees one element and pushes the others into another Vec, no view of them live; both Vecs read after
// Control for agora #490: moving a loop's element out is refused nowhere; only a borrow of the container's elements read after it is.
// map: §2.5 | A2 | runs-clean | - | agora #490: a loop that frees one element and pushes the others into another Vec, no view of them live; both Vecs read after
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `first string, long enough for a heap buffer` ) )
    ( vec_push [String] t ( string_from `second string, long enough for a heap buffer` ) )
    : ( Vec String ) u ( vec_new [String] )
    : ~ i n 0
    ~ x t { ? == n 0 { ( string_free x ) } { ( vec_push [String] u x ) } = n + n 1 }
    ~ y u { ( nurl_println ( string_data y ) ) }
    ( nurl_println ( string_data ( vec_at [String] t 0 ) ) )
    ^ 0
}

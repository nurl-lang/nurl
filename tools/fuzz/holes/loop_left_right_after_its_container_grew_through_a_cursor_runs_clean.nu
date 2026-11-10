// loop_left_right_after_its_container_grew_through_a_cursor_runs_clean: agora #493 — the growth through a cursor followed by `break`, growth after the loop, and an index loop that grows what it reads
// Control for agora #493: only a path that goes on to the loop's next element after the storage moved is refused.
// map: §2.5 | A2 | runs-clean | - | agora #493: the growth through a cursor followed by `break`, growth after the loop, and an index loop that grows what it reads
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    ( vec_push [String] t ( string_from `a second string long enough for a heap buffer` ) )
    : ~ ( Vec String ) cur t
    : ~ i n 0
    ~ x t {
        ( nurl_println ( string_data x ) )
        ~ < n 64 { ( vec_push [String] cur ( string_from `grow` ) ) = n + n 1 }
        break
    }
    ( vec_push [String] cur ( string_from `after` ) )
    : ~ i k 0
    ~ < k ( vec_len [String] t ) {
        ? < k 3 { ( vec_push [String] t ( string_from `more` ) ) } {}
        ( nurl_println ( string_data ( vec_at [String] t k ) ) )
        = k + k 1
    }
    ^ 0
}

// cursor_on_a_join_of_two_fields_cleared_with_no_borrow_runs_clean: agora #498 guard — `: ~ ( Vec Nd ) c ? own . u kids . t kids` cleared while no borrow of either arm is live, then the owner is read.
// Guard: the cursor borrows each arm; a clear through it with nothing else borrowed ends nothing that is read after.
// main: runs clean.
// map: §2.5 | A1 | runs-clean | - | agora #498 guard: a cursor on a join of two field paths cleared with no other borrow live
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Nd { ( Vec Nd ) kids String name }

@ mk String s → Nd { ^ @ Nd { ( vec_new [Nd] ) s } }

@ main → i {
    : ~ Nd t ( mk ( string_from `t` ) )
    : ~ Nd u ( mk ( string_from `u` ) )
    ( vec_push [Nd] . t kids ( mk ( string_from `a child name long enough for the heap` ) ) )
    : b own == ( vec_len [Nd] . u kids ) 1
    : ~ ( Vec Nd ) c ? own . u kids . t kids
    ( vec_clear [Nd] c )
    ( nurl_println_int ( vec_len [Nd] . t kids ) )
    ^ 0
}

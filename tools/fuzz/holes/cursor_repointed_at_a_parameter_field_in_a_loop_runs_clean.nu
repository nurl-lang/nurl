// cursor_repointed_at_a_parameter_field_in_a_loop_runs_clean: control: push, then `= c . x v`, in a loop and after a ?: a change through the cursor to the field it borrows is no end of its own borrow
// AGORA-869 (fpA-r8): the ownership engine's rule for it; the walk's verdict is the same.
// map: §2.10 | A2 | runs-clean | - | control: push, then `= c . x v`, in a loop and after a ?: a change through the cursor to the field it borrows is no end of its own borrow
$ `stdlib/core/vec.nu`

: App { ( Vec i ) v i n }

@ w App x → v {
    : ~ ( Vec i ) c ( vec_new [i] )
    : ~ i j 0
    ~ < j 3 {
        ( vec_push [i] c j )
        = c . x v
        = j + j 1
    }
}

@ g App x b k → v {
    : ~ ( Vec i ) c ( vec_new [i] )
    ? k { = c . x v } {}
    ( vec_push [i] c 1 )
    ( vec_push [i] c 2 )
}

@ main → i {
    : App a @ App { ( vec_new [i] ) 1 }
    ( w a ) ( g a T )
    ^ 0
}

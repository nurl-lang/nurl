// cursor_repointed_twice_at_a_parameter_field_runs_clean: control: a cursor given the same field read twice, pushed between
// AGORA-869 (fpA-r8): the ownership engine's rule for it; the walk's verdict is the same.
// map: §2.10 | A2 | runs-clean | - | control: a cursor given the same field read twice, pushed between
$ `stdlib/core/vec.nu`

: App { ( Vec i ) v i n }

@ w1 App x → v {
    : ~ ( Vec i ) c . x v
    : ~ i j 0
    ~ < j 3 {
        ( vec_push [i] c j )
        = c . x v
        = j + j 1
    }
}

@ w2 App x b k → v {
    : ~ ( Vec i ) c ( vec_new [i] )
    ? k { = c . x v } {}
    ( vec_push [i] c 1 )
    = c . x v
    ( vec_push [i] c 2 )
}

@ main → i {
    : App a @ App { ( vec_new [i] ) 1 }
    ( w1 a ) ( w2 a T )
    ^ 0
}

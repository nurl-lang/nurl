// drop_element_payload_of_an_arc_field_only_read_by_threads_runs_clean: eight threads each `?? ( vec_get [R] . ( arc_get [App] mine ) rs 0 ) { T e → { … ( peek e ) } … }`, R with its own `% Drop`, `peek` only reading it
// Guard for agora #763's fix: a payload of an Arc payload's element that is only read stays accepted.
// main 46338880: accepted, clean.
// map: §6.5 | A3 | runs-clean | - | agora #763 guard: threads reading a % Drop element of an Arc payload through a ?? payload stay accepted
$ `stdlib/core/vec.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`

: R { ( Vec i ) v i n }

% Drop R { @ drop R r → v {} }

: App { ( Vec R ) rs i n }

@ mkr → R { : ( Vec i ) v ( vec_new [i] ) ( vec_push [i] v 7 ) ^ @ R { v 1 } }

@ peek R r → i { ^ ( vec_len [i] . r v ) }

@ mkapp → ( Arc App ) { : ( Vec R ) rs ( vec_new [R] ) ( vec_push [R] rs ( mkr ) ) ^ ( arc_new [App] @ App { rs 0 } ) }

@ main → i {
    : ( Arc App ) app ( mkapp )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i j 0
    ~ < j 8 {
        : ( Arc App ) mine ( arc_clone [App] app )
        : !Thread ThreadErr r ( thread_spawn \ → v {
            : ~ i k 0
            : ~ i seen 0
            ~ < k 2000 {
                ?? ( vec_get [R] . ( arc_get [App] mine ) rs 0 ) { T e → { = seen + seen ( peek e ) } F → {} }
                = k + k 1
            }
            ? != seen 2000 { ( nurl_print `wrong\n` ) } {}
        } )
        ?? r { T t → { ( vec_push [Thread] ts t ) } F _ → { ( nurl_print `spawn fail\n` ) } }
        = j + j 1
    }
    = j 0
    ~ < j ( vec_len [Thread] ts ) {
        ?? ( vec_get [Thread] ts j ) { T t → { ( thread_join t ) } F _ → {} }
        = j + j 1
    }
    ( nurl_println `read 8 x 2000` )
    ^ 0
}

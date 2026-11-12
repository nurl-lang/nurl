// drop_element_payload_of_an_arc_field_changed_by_threads_is_refused: eight threads each `?? ( vec_get [R] . ( arc_get [App] mine ) rs 0 ) { T e → { ( rg e k ) } … }`, R with its own `% Drop`, `rg` growing its Vec field
// Closed: agora #763, the payload is a view of the Arc's payload, so the frozen-Arc rule sees the change.
// main 46338880: accepted (ASan: attempting double-free, in a worker thread).
// map: §6.5 | A3 | rejected | - | agora #763: a ?? payload of a % Drop element read out of an Arc payload's field, changed in a thread, is refused by the frozen-Arc rule
$ `stdlib/core/vec.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`

: R { ( Vec i ) v i n }

% Drop R { @ drop R r → v {} }

: App { ( Vec R ) rs i n }

@ mkr → R { : ( Vec i ) v ( vec_new [i] ) ( vec_push [i] v 7 ) ^ @ R { v 1 } }

@ rg R r i k → v { ( vec_push [i] . r v k ) }

@ mkapp → ( Arc App ) { : ( Vec R ) rs ( vec_new [R] ) ( vec_push [R] rs ( mkr ) ) ^ ( arc_new [App] @ App { rs 0 } ) }

@ main → i {
    : ( Arc App ) app ( mkapp )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i j 0
    ~ < j 8 {
        : ( Arc App ) mine ( arc_clone [App] app )
        : !Thread ThreadErr r ( thread_spawn \ → v {
            : ~ i k 0
            ~ < k 2000 {
                ?? ( vec_get [R] . ( arc_get [App] mine ) rs 0 ) { T e → { ( rg e k ) } F → {} }
                = k + k 1
            }
        } )
        ?? r { T t → { ( vec_push [Thread] ts t ) } F _ → { ( nurl_print `spawn fail\n` ) } }
        = j + j 1
    }
    = j 0
    ~ < j ( vec_len [Thread] ts ) {
        ?? ( vec_get [Thread] ts j ) { T t → { ( thread_join t ) } F _ → {} }
        = j + j 1
    }
    ^ 0
}

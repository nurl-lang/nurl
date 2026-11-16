// par_closure_local_repointed_at_an_accessor_lend_in_a_loop:
// AGORA-869: closed (main 3358873a: faulted under ASan); agora #696.
// map: §6.5 | A3 | rejected | - | agora #696: a closure par_map_index runs on eight threads pushes to a local, then `= c ( vof a )` (an accessor's lend of the capture) in the loop
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/std/par.nu`

: App { ( Vec i ) v i n }

@ vof App x → ( Vec i ) { ^ . x v }

@ main → i {
    : App a @ App { ( vec_new [i] ) 1 }
    : ( @ i i ) work \ i k → i {
        : ~ ( Vec i ) c ( vec_new [i] )
        : ~ i j 0
        ~ < j 400 { ( vec_push [i] c j ) = c ( vof a ) = j + j 1 }
        ^ k
    }
    : ( Vec i ) out ( par_map_index [i] 2000 8 work )
    ^ 0
}

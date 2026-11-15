// map: §6.5 | A3 | rejected | - | agora #696: a closure par_map_index runs on eight threads pushes to a local, then `= c . a v` in the loop: later rounds grow the capture's Vec with no lock
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/std/par.nu`

: App { ( Vec i ) v i n }

@ main → i {
    : App a @ App { ( vec_new [i] ) 1 }
    : ( @ i i ) work \ i k → i {
        : ~ ( Vec i ) c ( vec_new [i] )
        : ~ i j 0
        ~ < j 400 { ( vec_push [i] c j ) = c . a v = j + j 1 }
        ^ k
    }
    : ( Vec i ) out ( par_map_index [i] 2000 8 work )
    ^ 0
}

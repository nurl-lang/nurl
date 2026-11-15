// map: §6.5 | A3 | rejected | - | agora #696 guard: a closure par_map_index runs on eight threads does `= c . a v` and then pushes to c (the straight-line order)
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
        ~ < j 400 { = c . a v ( vec_push [i] c j ) = j + j 1 }
        ^ k
    }
    : ( Vec i ) out ( par_map_index [i] 2000 8 work )
    ^ 0
}

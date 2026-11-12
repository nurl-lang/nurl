// A diagnostic raised while a generic function is instantiated inside a
// function body (here the Send check at par_map_index's chan_send, for an
// Rc element) leaves that body mid-scope. The scope's module-scope pins
// table (nurl_sym_def_module) was in the compilation's table list as well
// as its owner's slot, so the exit sweep released it twice and nurlc died
// with SIGSEGV after printing the error (agora #715). It exits 1 now.
$ `stdlib/std/rc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`
$ `stdlib/std/par.nu`

: H { ( Rc i ) r }

@ main → i {
    : ( Vec H ) r ( par_map_index [H] 8 4 \ i k → H { ^ @ H { ( rc_new [i] k ) } } )
    ^ - ( vec_len [H] r ) 8
}

// A diagnostic raised while a generic function is instantiated, inside a
// closure in a nested block of its body (the Send check at a chan_send of
// an instance first named there), leaves that body mid-scope. The scope's
// module-scope pins table (nurl_sym_def_module) was in the compilation's
// table list as well as its owner's slot, so the exit sweep released it
// twice and nurlc died with SIGSEGV after printing the error (agora #715;
// stdlib/std/par.nu's par_map_index of an Rc element was the first shape).
// It exits 1 now.
$ `stdlib/std/rc.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/option.nu`

: Out [T] { i j T v }

@ send_all [T] i n ( @ T i ) f → i {
    : ~ i j 0
    ? > n 0 {
        : ( Channel ( Out T ) ) c ( chan_new [( Out T )] )
        : ( @ v ) body \ → v {
            : ~ i k 0
            ~ < k n {
                : b s ( chan_send [( Out T )] c @ ( Out T ) { k ( f k ) } )
                = k + k 1
            }
        }
        ( body )
    } {}
    ^ j
}

: H { ( Rc i ) r }

@ main → i {
    ^ ( send_all [H] 2 \ i k → H { ^ @ H { ( rc_new [i] k ) } } )
}

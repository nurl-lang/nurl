// A diagnostic raised while a generic function is instantiated, inside a
// closure in a nested block of its body (the Send check at a chan_send,
// after an instance is first named there), leaves that body mid-scope.
// The scope's module-scope pins table (nurl_sym_def_module) was in the
// compilation's table list as well as its owner's slot, so the exit sweep
// released it twice and nurlc died with SIGSEGV after printing the error
// (agora #715; stdlib/std/par.nu's par_map_index of an Rc element was the
// first shape). It exits 1 now. (The value is on a line of its own: on the
// line of `[T]` a re-read template's columns drift, agora #751.)
$ `stdlib/std/rc.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/option.nu`

: Out [T] { i j T v }

@ send_all [T] i n ( @ T i ) f → i {
    : ~ i j 0
    ? > n 0 {
        : ( Channel ( Out T ) ) c ( chan_new [( Out T )] )
        : ( Channel T ) d ( chan_new [T] )
        : ( @ v ) body \ → v {
            : ~ i k 0
            ~ < k n {
                : b s ( chan_send [T] d
                ( f k ) )
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

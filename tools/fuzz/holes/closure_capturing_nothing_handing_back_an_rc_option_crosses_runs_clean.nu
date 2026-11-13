// closure_capturing_nothing_handing_back_an_rc_option_crosses_runs_clean: closures that capture nothing and hand back a fresh `?( Rc i )`, run by threads out of a capture, a struct in a Vec and an Arc
// Guard for agora #788's fix: a closure is asked by its captures, not by the types its code hands back.
// main ad17e78c: refused, by the closure's signature ("captures 'f' … reaches an 'Rc'").
// map: §6.5 | A3 | runs-clean | - | agora #788 guard: a closure that captured nothing crosses whatever its signature names
$ `stdlib/std/rc.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

@ run_n ( @ ?( Rc i ) i ) f i n → i {
    : ~ i k 0
    : ~ i s 0
    ~ < k n {
        ?? ( f k ) { T x → { = s + s ( rc_get [i] x ) } F → {} }
        = k + k 1
    }
    ^ s
}

: H { ( @ ?( Rc i ) i ) f i n }

@ main → i {
    : ( @ ?( Rc i ) i ) f \ i k → ?( Rc i ) { ^ @ ?( Rc i ) { T ( rc_new [i] 1 ) } }
    ?? ( thread_spawn \ → v { ( nurl_println_int ( run_n f 20000 ) ) } ) { T t → { ( thread_join t ) } F _ → {} }
    : ( Vec H ) hs ( vec_new [H] )
    ( vec_push [H] hs @ H { \ i k → ?( Rc i ) { ^ @ ?( Rc i ) { T ( rc_new [i] 2 ) } } 1 } )
    ?? ( thread_spawn \ → v { ( nurl_println_int ( run_n . ( vec_at [H] hs 0 ) f 20000 ) ) } ) { T t → { ( thread_join t ) } F _ → {} }
    : ( Arc H ) a ( arc_new [H] @ H { \ i k → ?( Rc i ) { ^ @ ?( Rc i ) { T ( rc_new [i] 3 ) } } 1 } )
    : ( Arc H ) mine ( arc_clone [H] a )
    ?? ( thread_spawn \ → v { ( nurl_println_int ( run_n . ( arc_get [H] mine ) f 20000 ) ) } ) { T t → { ( thread_join t ) } F _ → {} }
    ^ 0
}

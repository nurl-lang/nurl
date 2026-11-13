// closure_in_a_struct_in_a_vec_run_on_one_thread_runs_clean: a Holder with a closure that gives away its capture, pushed into a Vec and run on one thread
// Guard for agora #665's fix: a Vec of closures used on one thread is accepted.
// main 2faf34c2: accepted, clean.
// map: §6.5 | A3 | runs-clean | - | agora #665 guard: a struct-held closure in a Vec run on its own thread stays accepted
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/atomic.nu`

: App { ( Vec String ) log i n }
: Holder { ( @ i i ) f i tag }

@ eatapp sink App x → v {}

@ mk i n → App { : ~ ( Vec String ) l ( vec_new [String] ) ( vec_push [String] l ( string_from `one` ) ) ^ @ App { l n } }

@ main → i {
    : Atomic gate ( atomic_new 0 )
    : Atomic gw ( mem_dup gate )
    : App a ( mk 2 )
    : ( @ i i ) work \ i k → i { ~ == ( atomic_load gw ) 0 {} ( eatapp a ) ^ k }
    : Holder hd @ Holder { work 7 }
    : ~ ( Vec Holder ) hv ( vec_new [Holder] )
    ( vec_push [Holder] hv hd )
    : Holder h ( vec_at [Holder] hv 0 )
    : ( @ i i ) g . h f
    ( atomic_store gate 1 )
    ( nurl_println_int ( g 1 ) )
    ^ 0
}

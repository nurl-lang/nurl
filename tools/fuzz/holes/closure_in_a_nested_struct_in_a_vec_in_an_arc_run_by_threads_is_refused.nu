// closure_in_a_nested_struct_in_a_vec_in_an_arc_run_by_threads_is_refused: the same with the closure in a struct nested in the struct
// Closed: agora #665, the capture set follows a closure into a struct, an option, an enum payload or a Vec it is handed to.
// main 2faf34c2: accepted (eight threads run one env: the run-once panic, or a double free).
// map: §6.5 | A3 | rejected | - | agora #665: a closure in a nested struct in a Vec in an Arc is held to the Sync-closure rule
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/atomic.nu`

: App { ( Vec String ) log i n }
: Inner { ( @ i i ) f i tag }
: Holder { Inner in i tag }

@ eatapp sink App x → v {}

@ mk i n → App { : ~ ( Vec String ) l ( vec_new [String] ) ( vec_push [String] l ( string_from `one` ) ) ^ @ App { l n } }

@ main → i {
    : Atomic gate ( atomic_new 0 )
    : Atomic gw ( mem_dup gate )
    : App a ( mk 2 )
    : ( @ i i ) work \ i k → i { ~ == ( atomic_load gw ) 0 {} ( eatapp a ) ^ k }
    : Holder hd @ Holder { @ Inner { work 1 } 7 }
    : ~ ( Vec Holder ) hv ( vec_new [Holder] )
    ( vec_push [Holder] hv hd )
    : ( Arc ( Vec Holder ) ) shared ( arc_new [( Vec Holder )] hv )
    : ~ ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 8 {
        : ( Arc ( Vec Holder ) ) mine ( arc_clone [( Vec Holder )] shared )
        ?? ( thread_spawn \ → v {
            : ( Vec Holder ) vv ( arc_get [( Vec Holder )] mine )
            : Holder h ( vec_at [Holder] vv 0 )
            : ( @ i i ) g . . h in f
            ( g 1 )
        } ) { T th → ( vec_push [Thread] ts th ) F e → {} }
        = t + t 1
    }
    ( atomic_store gate 1 )
    : ~ i j 0
    ~ < j ( vec_len [Thread] ts ) { ( thread_join ( vec_at [Thread] ts j ) ) = j + j 1 }
    ^ 0
}

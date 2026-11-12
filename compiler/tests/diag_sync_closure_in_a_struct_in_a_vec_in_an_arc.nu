// diag_sync_closure_in_a_struct_in_a_vec_in_an_arc.nu — a struct holding a
// closure that gives away what it captured, pushed into a Vec kept in an
// Arc that eight threads read: the Arc's payload holds the closure, so the
// Sync-closure rule refuses it, as for the struct put in the Arc directly
// (Agora #665).
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
    : ( Arc ( Vec Holder ) ) shared ( arc_new [( Vec Holder )] hv )
    : ~ ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 8 {
        : ( Arc ( Vec Holder ) ) mine ( arc_clone [( Vec Holder )] shared )
        ?? ( thread_spawn \ → v {
            : ( Vec Holder ) vv ( arc_get [( Vec Holder )] mine )
            : Holder h ( vec_at [Holder] vv 0 )
            : ( @ i i ) g . h f
            ( g 1 )
        } ) { T th → ( vec_push [Thread] ts th ) F e → {} }
        = t + t 1
    }
    ( atomic_store gate 1 )
    : ~ i j 0
    ~ < j ( vec_len [Thread] ts ) { ( thread_join ( vec_at [Thread] ts j ) ) = j + j 1 }
    ^ 0
}

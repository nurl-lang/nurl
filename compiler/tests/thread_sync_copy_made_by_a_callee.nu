// thread_sync_copy_made_by_a_callee.nu — what a call hands back is judged
// by what the callee lends, not by what it was handed (docs/MEMORY.md
// §6.5; agora #639). A closure several threads run may change a copy of
// what it captured: a `vec_clone` of a captured field, a `vec_map` over
// the payload of a `??`, a struct a function defined below it built out
// of copies. So may the function an Arc's payload is handed to. A generic
// is compiled where it is first used and a function may be defined below
// its caller: neither is known when the call is read, and both are judged
// by the summary they end with.
//
// The control for diag_sync_closure_callee_below_lends_its_argument.nu
// (the callee lends: the change is the capture's) and for
// diag_sync_closure_copy_written_over_in_a_loop.nu (the local that held
// the copy is given the capture's own handle further down).
//
// Spawns real pthreads, so it carries the same declaration as
// thread_basic / arc_threads.
// requires: live

$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: Inner { ( Vec i ) v String label }

: App { ( Vec i ) v ? ( Vec i ) ov ( Vec Inner ) ins Atomic hits }

: Box { ( Vec i ) v i n }

@ mkapp → App {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 )
    ( vec_push [i] v 2 )
    : ( Vec i ) o ( vec_new [i] )
    ( vec_push [i] o 3 )
    : ( Vec Inner ) ins ( vec_new [Inner] )
    : ( Vec i ) iv ( vec_new [i] )
    ( vec_push [i] iv 4 )
    ( vec_push [Inner] ins @ Inner { iv ( string_from `a label long enough to live on the heap` ) } )
    ^ @ App { v @ ?( Vec i ) { T o } ins ( atomic_new 0 ) }
}

// An Arc's payload handed to a function that changes copies only: one
// made by a function above it, one by a function below it.
@ copy_of App x Inner r → ( Vec i ) { ^ ( vec_clone [i] . r v ) }

@ tally App x i k → i {
    : Inner r ( vec_at [Inner] . x ins 0 )
    : ( Vec i ) c ( copy_of x r )
    ( vec_push [i] c k )
    : String line ( label_of x r )
    ( string_push_str line `!` )
    ^ + ( vec_len [i] c ) ( string_len line )
}

@ label_of App x Inner r → String { ^ ( string_clone . r label ) }

@ main → i {
    : App app ( mkapp )

    // 1 — a closure kept in an Arc: every thread holding a copy runs it.
    : ( @ v i ) work \ i k → v {
        // A copy of a captured field, grown here and in a loop.
        : ( Vec i ) c ( vec_clone [i] . app v )
        ( vec_push [i] c k )
        : ~ i j 0
        ~ < j 3 {
            ( vec_push [i] c j )
            = j + j 1
        }
        : i seen ( atomic_add . app hits ( vec_len [i] c ) )
        // A new Vec made out of the payload of a `??`.
        ?? . app ov {
            T p → {
                : ( Vec i ) d ( vec_map [i i] p \ i e → i { ^ * e 2 } )
                ( vec_push [i] d k )
                : i more ( atomic_add . app hits ( vec_len [i] d ) )
            }
            F → {}
        }
        // A struct of copies, built by a function defined below.
        : ~ Box w ( boxed app )
        = . w n k
        ( vec_push [i] . w v k )
        : i last ( atomic_add . app hits + . w n ( vec_len [i] . w v ) )
    }
    : ( Arc ( @ v i ) ) shared ( arc_new [( @ v i )] work )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i w 0
    ~ < w 4 {
        : ( Arc ( @ v i ) ) mine ( arc_clone [( @ v i )] shared )
        : ( @ v ) body \ → v {
            : ~ i j 0
            ~ < j 250 {
                : ( @ v i ) run ( arc_get [( @ v i )] mine )
                ( run 1 )
                = j + j 1
            }
        }
        ?? ( thread_spawn body ) {
            T t → { ( vec_push [Thread] ts t ) }
            F e → { ( nurl_print `spawn fail\n` ) }
        }
        = w + w 1
    }
    : ~ i q 0
    ~ < q ( vec_len [Thread] ts ) { : i joined ( thread_join ( vec_at [Thread] ts q ) ) = q + q 1 }
    // Each run adds 6 + 2 + 4; nothing the closure captured was changed.
    ( nurl_print ( nurl_str_int ( atomic_load . app hits ) ) ) ( nurl_print `\n` )
    ( nurl_print ( nurl_str_int ( vec_len [i] . app v ) ) ) ( nurl_print `\n` )

    // 2 — an Arc's payload is frozen; a copy of a part of it is not.
    : ( Arc App ) held ( arc_new [App] ( mkapp ) )
    ( nurl_print ( nurl_str_int ( tally ( arc_get [App] held ) 5 ) ) ) ( nurl_print `\n` )
    ( nurl_print ( nurl_str_int ( vec_len [i] . ( vec_at [Inner] . ( arc_get [App] held ) ins 0 ) v ) ) ) ( nurl_print `\n` )
    ^ 0
}

@ boxed App x → Box { ^ @ Box { ( vec_clone [i] . x v ) 0 } }

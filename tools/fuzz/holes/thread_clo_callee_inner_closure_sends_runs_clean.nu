// thread_clo_callee_inner_closure_sends_runs_clean: a callee of a thread-shared value whose inner closure only reads or sends (d15_clo_callee_inner_closure_sends)
// Kept: a closure that only reads what it captured, or its own parameter, changes nothing of the caller's (agora #656).
// main 820aafb4: accepted; runs clean under AddressSanitizer.
// map: §2.10 | A2 | runs-clean | - | agora #656: an inner closure of a thread-shared callee that only reads
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`

: Inner { ( Vec i ) v ( Channel i ) c i n }
: App { ( Channel i ) h ( Vec i ) v ( Vec ( Channel i ) ) hs Inner in ? ( Vec i ) ov ( Vec ( Vec i ) ) vv ? ( Channel i ) oh ( Vec Inner ) ins ( Vec String ) names i n }
: Holder { ( @ i i ) f i tag }

@ mkapp → App {
    : ( Vec ( Channel i ) ) hs ( vec_new [( Channel i )] )
    ( vec_push [( Channel i )] hs ( chan_new [i] ) )
    : ( Vec ( Vec i ) ) vv ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] vv ( vec_new [i] ) )
    : ( Vec Inner ) ins ( vec_new [Inner] )
    ( vec_push [Inner] ins @ Inner { ( vec_new [i] ) ( chan_new [i] ) 0 } )
    : ( Vec String ) names ( vec_new [String] )
    ( vec_push [String] names ( string_from `a name long enough to live on the heap, not inline` ) )
    ^ @ App { ( chan_new [i] ) ( vec_new [i] ) hs @ Inner { ( vec_new [i] ) ( chan_new [i] ) 0 } @ ?( Vec i ) { T ( vec_new [i] ) } vv @ ?( Channel i ) { T ( chan_new [i] ) } ins names 1 }
}

@ hit ( Arc Holder ) a i n → i {
    : Holder h ( arc_get [Holder] a )
    : ( @ i i ) g . h f
    : ~ i j 0
    : ~ i last 0
    ~ < j n {
        = last ( g j )
        = j + j 1
    }
    ^ last
}

@ w App x → v { : ( @ v ) c \ → v { ( chan_send [i] . x h 1 ) } ( c ) }

@ main → i {
    : App a ( mkapp )
    : ( @ i i ) work \ i k → i {
        ( w a )
        ^ k
    }
    : Holder hd @ Holder { work 7 }
    : ( Arc Holder ) shared ( arc_new [Holder] hd )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 8 {
        : ( Arc Holder ) mine ( arc_clone [Holder] shared )
        : ( @ v ) body \ → v { : i n ( hit mine 3000 ) }
        ?? ( thread_spawn body ) {
            T th → { ( vec_push [Thread] ts th ) }
            F e → { ( nurl_eprintln `spawn failed` ) }
        }
        = t + t 1
    }
    : ~ i q 0
    ~ < q ( vec_len [Thread] ts ) { : i joined ( thread_join ( vec_at [Thread] ts q ) ) = q + q 1 }
    ( nurl_eprintln `ran` )
    ^ 0
}

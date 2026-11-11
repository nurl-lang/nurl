// sync_value_sunk_by_a_shared_closure: a closure four threads run hands a field of its captured struct — a type asserted Sync — to a function that takes it over (`sink`) and so releases it, once per call, on every thread. A value that synchronises itself answers for the changes made through it (agora #639), not for its own end.
// Guard of #639's rule: by-value passes only.
// map: §6.5 | A3 | rejected | - | a thread-shared closure hands its captured struct's Sync-asserted field to a sink parameter: a self-synchronising value does not answer for its own end (agora #639)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: Tally { Atomic sum ( Vec i ) seen }

unsafe % Sync Tally {}

@ tally_close sink Tally t → i { ^ ( atomic_load . t sum ) }

: Board { Tally tally i n }

@ main → i {
    : ( Vec i ) first ( vec_new [i] )
    ( vec_push [i] first 0 )
    : Board board @ Board { @ Tally { ( atomic_new 0 ) first } 1 }
    : ( @ v i ) work \ i k → v { : i last ( tally_close . board tally ) }
    : ( Arc ( @ v i ) ) shared ( arc_new [( @ v i )] work )
    : ( Vec ( Thread ) ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 4 {
        : ( Arc ( @ v i ) ) mine ( arc_clone [( @ v i )] shared )
        : ( @ v ) body \ → v {
            : ~ i j 0
            ~ < j 2000 {
                : ( @ v i ) run ( arc_get [( @ v i )] mine )
                ( run j )
                = j + j 1
            }
        }
        ?? ( thread_spawn body ) {
            T th → { ( vec_push [Thread] ts th ) }
            F _ → {}
        }
        = t + t 1
    }
    ~ > ( vec_len [Thread] ts ) 0 { ?? ( vec_pop [Thread] ts ) { T th → { : i joined ( thread_join th ) } F → {} } }
    ^ 0
}

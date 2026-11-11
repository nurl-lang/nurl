// sync_value_storage_refilled_through_inout_by_a_shared_closure: a closure four threads run hands a field of its captured struct — a type asserted Sync — to a function that takes it `inout` and gives it a new value. A change made THROUGH a value that synchronises itself is the value's own when it is borrowed by value (agora #639); an `inout` parameter is the place the holder keeps it, which every thread reads with no lock, and the old value is released under them.
// Guard of #639's rule: by-value passes only.
// map: §6.5 | A3 | rejected | - | a thread-shared closure hands its captured struct's Sync-asserted field to an inout parameter that refills it: the storage of a self-synchronising value is not synchronised by it (agora #639)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: Tally { Atomic sum ( Vec i ) seen }

unsafe % Sync Tally {}

@ tally_reset inout Tally t i k → v {
    : ( Vec i ) fresh ( vec_new [i] )
    ( vec_push [i] fresh k )
    = t @ Tally { ( atomic_new k ) fresh }
}

: Board { Tally tally i n }

@ main → i {
    : ( Vec i ) first ( vec_new [i] )
    ( vec_push [i] first 0 )
    : ~ Board board @ Board { @ Tally { ( atomic_new 0 ) first } 1 }
    : ( @ v i ) work \ i k → v { ( tally_reset . board tally k ) }
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

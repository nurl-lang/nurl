// strings_in_a_locked_global_and_a_table_in_an_arc_global_used_by_two_threads_runs_clean: the valid side of the globals set at start. A `( Locked ( Vec String ) )` is grown by two threads, each holding the lock; an `( Arc Table )` of plain data is read by both; a `( Channel String )` carries Strings from one to the other. What each holds is safe where its handle puts it — a Locked's and a Channel's value Send, an Arc's payload Sync — so the three stay accepted.
// map: §6.5 | A3 | runs-clean | - | globals set at start holding Send values in a Locked and a Channel and a Sync payload in an Arc, used by two threads (agora #639)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/std/thread.nu`

: Table { ( Vec String ) names i scale }

@ make_log → ( Locked ( Vec String ) ) { ^ ( locked_new [( Vec String )] ( vec_new [String] ) ) }

@ make_table → ( Arc Table ) {
    : ( Vec String ) ns ( vec_new [String] )
    ( vec_push [String] ns ( string_from `a table entry that is long enough to live on the heap` ) )
    ( vec_push [String] ns ( string_from `another table entry that is long enough to live on the heap` ) )
    ^ ( arc_new [Table] @ Table { ns 3 } )
}

@ make_queue → ( Channel String ) { ^ ( chan_new [String] ) }

: ( Locked ( Vec String ) ) g_log ( make_log )

: ( Arc Table ) g_table ( make_table )

: ( Channel String ) g_queue ( make_queue )

@ note i k → v {
    : Table t ( arc_get [Table] g_table )
    : String line ( string_from ( string_data ( vec_at [String] . t names % k 2 ) ) )
    : ~ ( Vec String ) log ( locked_take [( Vec String )] g_log )
    ( vec_push [String] log line )
    ( locked_restore [( Vec String )] g_log log )
}

@ churn i n → v {
    : ~ i k 0
    ~ < k n { ( note k ) = k + k 1 }
}

@ main → i {
    ?? ( thread_spawn \ → v {
        ( churn 2000 )
        ( chan_send [String] g_queue ( string_from `the worker is done, and says so in a heap string` ) )
    } ) {
        T t → {
            ( churn 2000 )
            : ?String done ( chan_recv [String] g_queue )
            ( thread_join t )
        }
        F _ → {}
    }
    : ~ ( Vec String ) log ( locked_take [( Vec String )] g_log )
    : i n ( vec_len [String] log )
    ( locked_restore [( Vec String )] g_log log )
    ^ ? == n 4000 0 1
}

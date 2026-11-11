// arc_payload_copies_grown_and_sunk_by_its_reader_runs_clean: a function handed an Arc's payload, on eight threads, changes nothing but copies: a `vec_clone` of a field it pushes to, the results of two copying helpers DEFINED BELOW it handed to a function that grows them, and an element bound to a name handed to a `sink` parameter (which is handed a copy: a take of a part of a borrow is refused).
// None is a change of the frozen payload. Guards of agora #646's derived edges: a value a callee with no summary yet hands back is read out of the callee's arguments only where its final summary lends them (a helper defined below its caller, an instance of a generic first asked for here), and what a `sink` parameter does to the value it is handed is no change of what the value was read out of.
// map: ThruOK.noShare | A3 | runs-clean | - | a function handed `( arc_get a )` grows a `vec_clone` of a field, hands copies made by helpers defined below it to a grower, and an element bound to a name to a sink: changes of copies, none of the frozen payload (agora #646)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: Meta { i id String name ( Vec String ) names ( Vec i ) log }

: App { Meta m ( Channel i ) jobs }

@ mkapp → App {
    : ( Vec String ) names ( vec_new [String] )
    ( vec_push [String] names ( string_from `a name that is long enough to be on the heap` ) )
    : ( Vec i ) log ( vec_new [i] )
    ( vec_push [i] log 7 )
    ^ @ App { @ Meta { 1 ( string_from `a table name long enough to be on the heap` ) names log } ( chan_new [i] ) }
}

@ keep sink String x → i { ^ ( string_len x ) }

@ grow String x → i {
    ( string_push_str x `!` )
    ^ ( string_len x )
}

@ rd Meta m i k → i {
    // a library-made copy, grown by its maker
    : ( Vec i ) mine ( vec_clone [i] . m log )
    ( vec_push [i] mine k )
    // copies made by helpers defined below this function, grown by a callee
    : i a ( grow ( dupname m ) )
    : i b ( grow ( dupfirst m ) )
    // an element bound to a name, handed to a sink: the sink gets a copy
    : i c ( sunk m )
    ^ + + + a b c ( vec_len [i] mine )
}

@ sunk Meta m → i {
    : String e ( vec_at [String] . m names 0 )
    ^ ( keep e )
}

@ dupname Meta m → String { ^ ( string_clone . m name ) }

@ dupfirst Meta m → String { ^ ( string_clone ( vec_at [String] . m names 0 ) ) }

@ reader ( Arc App ) mine i n → v {
    : ~ i k 0
    ~ < k n {
        : i got ( rd . ( arc_get [App] mine ) m k )
        = k + k 1
    }
}

@ main → i {
    : ( Arc App ) shared ( arc_new [App] ( mkapp ) )
    : ( Vec ( Thread ) ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 8 {
        : ( Arc App ) mine ( arc_clone [App] shared )
        : ( @ v ) body \ → v { ( reader mine 3000 ) }
        ?? ( thread_spawn body ) {
            T th → { ( vec_push [Thread] ts th ) }
            F _ → {}
        }
        = t + t 1
    }
    ~ > ( vec_len [Thread] ts ) 0 { ?? ( vec_pop [Thread] ts ) { T th → { : i joined ( thread_join th ) } F → {} } }
    ^ 0
}

// arc_payload_checked_by_a_function_that_panics_from_two_places_runs_clean: a function handed an Arc's payload, on eight threads, validates a row against the payload's column list and reports an error from two places with `( panic_with ( string_concat … ( string_clone . m name ) … ) )` — a message built from copies of the payload's strings. It changes nothing of the payload.
// Guard of agora #646's derived edges: a summary edge noted at two calls under two conditions is there where either holds. Narrowed to what the two conditions share — nothing — it held always, and the function was summarised as handing its parameter's strings to `panic_with` (nurldb's row check, refused as a change of the frozen table).
// map: ThruOK.noShare | A3 | runs-clean | - | a function handed `( arc_get a )` reports errors from two places with `panic_with` over copies of the payload's strings: a conditioned summary edge noted at two calls holds where either condition does, and here neither (agora #646)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/panic.nu`

: ColDef { String name i ty b notnull }

: TableMeta { i id String name ( Vec ColDef ) cols }

: App { TableMeta m ( Channel i ) jobs }

@ mkapp → App {
    : ( Vec ColDef ) cols ( vec_new [ColDef] )
    ( vec_push [ColDef] cols @ ColDef { ( string_from `a column name long enough to be on the heap` ) 1 F } )
    ^ @ App { @ TableMeta { 1 ( string_from `a table name long enough to be on the heap` ) cols } ( chan_new [i] ) }
}

@ coerce TableMeta m ( Vec i ) row → ( Vec i ) {
    : i n ( vec_len [ColDef] . m cols )
    ? != ( vec_len [i] row ) n { ( panic_with ( string_concat ( string_from `table ` ) ( string_concat ( string_clone . m name ) ( string_from ` has a different number of columns` ) ) ) ) } {}
    : ( Vec i ) out ( vec_with_cap [i] n )
    : ~ i k 0
    ~ < k n {
        : ColDef c ( vec_at [ColDef] . m cols k )
        : i x ( vec_at [i] row k )
        ? == x 0 {
            ? . c notnull { ( panic_with ( string_concat ( string_from `NULL in ` ) ( string_clone . c name ) ) ) } {}
            ( vec_push [i] out 0 )
        } {
            ( vec_push [i] out x )
        }
        = k + k 1
    }
    ^ out
}

@ reader ( Arc App ) mine i n → v {
    : ~ i k 0
    ~ < k n {
        : ( Vec i ) row ( vec_new [i] )
        ( vec_push [i] row + k 1 )
        : ( Vec i ) r ( coerce . ( arc_get [App] mine ) m row )
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

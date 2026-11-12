// returned_calls_judged_before_the_ret_still_accept_lends_runs_clean: returns whose calls are now judged before the `ret` row, and which main accepts and run clean: a `??` payload's field handed back through an option (a lend), a value moved into the returned option, a copy of a borrowed field handed to a sink, a read-only call on a borrowed field
// Guard for agora #680's fix: only the calls' rows go before the `ret` row (__bck_ret_flush_ppends) — what the return itself moves into its value stays the `ret` row's.
// main 0b3f239a: accepted, clean.
// map: §2.10 | A2 | runs-clean | - | agora #680 guard: a returned lend, a move into the result, a copy to a sink and a read-only call stay accepted
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: Ent { String key String value }

@ keep sink String x → i { ^ ( string_len x ) }

@ get ( Vec Ent ) es s key → ?String {
    : i n ( vec_len [Ent] es )
    : ~ i k 0
    ~ < k n {
        : ?Ent ek ( vec_get [Ent] es k )
        ?? ek {
            T ev → {
                ? ( nurl_str_eq ( string_data . ev key ) key ) {
                    ^ @ ?String { T . ev value }
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ @ ?String { F }
}

@ wrap → ?String {
    : String x ( string_from `a value long enough to live on the heap` )
    ^ @ ?String { T x }
}

@ copy_len ( Vec Ent ) es → i {
    : Ent e ( vec_at [Ent] es 0 )
    ^ ( keep ( string_clone . e value ) )
}

@ read_len ( Vec Ent ) es → i {
    : Ent e ( vec_at [Ent] es 0 )
    ^ ( string_len . e key )
}

@ main → i {
    : ( Vec Ent ) es ( vec_new [Ent] )
    ( vec_push [Ent] es @ Ent { ( string_from `the key, long enough for the heap` ) ( string_from `the value, long enough for the heap` ) } )
    : ~ i t 0
    ?? ( get es `the key, long enough for the heap` ) {
        T v → { = t + t ( string_len v ) }
        F → {}
    }
    ?? ( wrap ) {
        T w → { = t + t ( string_len w ) }
        F → {}
    }
    = t + t ( copy_len es )
    = t + t ( read_len es )
    ^ ? > t 0 0 1
}

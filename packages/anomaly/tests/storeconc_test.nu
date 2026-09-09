// tests/storeconc_test.nu — several threads, one organisation's database.
//
// The store keeps no connection: each operation opens one, uses it and
// closes it, so a Store may be copied into a thread and every thread talks
// to the same FILE over its own handle. This is the proof that it holds —
// four threads writing at once into one database, then one reader counting
// what arrived.
//
// What is being tested is the storage layer, not the model layer: each
// thread owns its own model name, because two threads doing a
// read-modify-write of ONE model can still lose an update and that is the
// service's lock to hold, not the store's.
//
// Store root: $ANOMALY_TEST_DIR (default ./anomaly_storeconc_test).

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/json.nu`
$ `src/prep.nu`
$ `src/model.nu`
$ `src/score.nu`
$ `src/store.nu`

: ~ i g_pass 0
: ~ i g_fail 0

@ pline s x → v {
    ( nurl_print x )
    ( nurl_print `\n` )
}

@ check b cond s label → v {
    ? cond {
        ( nurl_print `ok ` ) ( pline label )
        = g_pass + g_pass 1
    } {
        ( nurl_print `FAIL ` ) ( pline label )
        = g_fail + g_fail 1
    }
}

: i CONC_THREADS 4
: i CONC_POINTS 150

// One worker: its own model, CONC_POINTS points into the shared database,
// each one its own transaction, with an eviction once past the cap.
@ worker s root s name → v {
    : Store st ( store_open root )
    : *Meta m ( meta_new name `2026-01-01T00:00:00Z` )
    : ~ i k 0
    ~ < k CONC_POINTS {
        : String line ( string_from `{"temp":` )
        ( string_push_int line k )
        ( string_push_str line `,"timestamp":` )
        ( string_push_int line + 1700000000 k )
        ( string_push_char line 125 )
        = . m n_seen + k 1
        // Keep the newest 100: past that every point evicts one.
        : ~ i evict 0
        ? > + k 1 100 { = evict - + k 1 100 } {}
        ( store_commit_point st name k ( string_data line ) evict m )
        ( string_free line )
        = k + k 1
    }
    ( meta_free m )
    ( store_free st )
}

@ main → i {
    : ~ String root ( string_from `./anomaly_storeconc_test` )
    ?? ( env_get `ANOMALY_TEST_DIR` ) {
        T d → { ( string_free root ) = root d }
        F _ → {}
    }
    : !v IoErr junk ( dir_remove_all ( string_data root ) )
    ?? junk { T _ → {} F _ → {} }

    // Create the database once, so the threads race on the tables rather
    // than on creating them.
    : Store seed ( store_open ( string_data root ) )
    ( check . seed ok `conc: the organisation's database opens` )
    ( store_free seed )

    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ( Vec String ) names ( vec_new [String] )
    : ~ i t 0
    ~ < t CONC_THREADS {
        : String nm ( string_from `w` )
        ( string_push_int nm t )
        ( vec_push [String] names nm )
        = t + t 1
    }
    = t 0
    ~ < t CONC_THREADS {
        ?? ( vec_get [String] names t ) {
            T nm → {
                : String r2 ( string_clone root )
                : String n2 ( string_clone nm )
                : ( @ v ) body \ → v {
                    ( worker ( string_data r2 ) ( string_data n2 ) )
                    ( string_free r2 )
                    ( string_free n2 )
                }
                ?? ( thread_spawn_owned body ) {
                    T th → { ( vec_push [Thread] ts th ) }
                    F _ → { ( check F `conc: a worker thread started` ) }
                }
            }
            F _ → {}
        }
        = t + t 1
    }
    ( check == ( vec_len [Thread] ts ) CONC_THREADS `conc: every worker thread started` )
    : i nt ( vec_len [Thread] ts )
    = t 0
    ~ < t nt {
        ?? ( vec_get [Thread] ts t ) { T th → { : i _rc ( thread_join th ) } F _ → {} }
        = t + t 1
    }

    // Every worker's ring is there, at its cap, and holds ITS OWN points.
    : Store st ( store_open ( string_data root ) )
    : ( Vec String ) listed ( store_list st )
    ( check == ( vec_len [String] listed ) CONC_THREADS `conc: every worker's model is in the database` )
    ( vec_free_with [String] listed \ String x → v { ( string_free x ) } )
    : ~ b counts_ok T
    : ~ b content_ok T
    = t 0
    ~ < t CONC_THREADS {
        ?? ( vec_get [String] names t ) {
            T nm → {
                ? == ( store_points_count st ( string_data nm ) ) 100 {} { = counts_ok F }
                : ( Vec String ) tail ( store_load_points_tail st ( string_data nm ) 1 )
                ?? ( vec_get [String] tail 0 ) {
                    T last → {
                        : String want ( string_from `{"temp":` )
                        ( string_push_int want - CONC_POINTS 1 )
                        ( string_push_char want 44 )
                        ? ( string_contains last ( string_data want ) ) {} { = content_ok F }
                        ( string_free want )
                    }
                    F _ → { = content_ok F }
                }
                ( vec_free_with [String] tail \ String x → v { ( string_free x ) } )
            }
            F _ → {}
        }
        = t + t 1
    }
    ( check counts_ok `conc: each ring holds exactly its cap after concurrent eviction` )
    ( check content_ok `conc: and its newest point is the last one that thread wrote` )
    ( store_free st )
    ( vec_free [Thread] ts )
    ( vec_free_with [String] names \ String x → v { ( string_free x ) } )

    : !v IoErr fin ( dir_remove_all ( string_data root ) )
    ?? fin { T _ → {} F _ → {} }
    ( string_free root )

    : String summary ( string_from `storeconc_test: ` )
    ( string_push_int summary g_pass )
    ( string_push_str summary ` passed, ` )
    ( string_push_int summary g_fail )
    ( string_push_str summary ` failed` )
    ( pline ( string_data summary ) )
    ( string_free summary )
    ? > g_fail 0 { ^ 1 } {}
    ^ 0
}

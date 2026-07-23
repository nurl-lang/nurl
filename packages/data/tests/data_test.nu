// data_test.nu — DataLoader gates: deterministic seeded shuffle, exactly-
// once epoch coverage, drop-last, shard partitioning, and streamed batches
// equal to in-memory batches. Each example carries its own id in y[0], so
// coverage and order are checked directly regardless of feature values.
//
//   NURL_STDLIB=<repo> ../../nurl.sh tests/data_test.nu /tmp/dt && /tmp/dt

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `src/data.nu`

: ~ i g_pass 0

: ~ i g_fail 0

@ check b ok s label → v {
    ? ok { ( nurl_print `  ok ` ) = g_pass + g_pass 1 } { ( nurl_print `  FAIL ` ) = g_fail + g_fail 1 }
    ( nurl_print label ) ( nurl_print `\n` )
}

@ gf ( Vec f ) v i k → f { ?? ( vec_get [f] v k ) { T x → x F → 0.0 } }

@ gi ( Vec i ) v i k → i { ?? ( vec_get [i] v k ) { T x → x F → 0 } }

// dataset of n examples, d=2 features [i, i*10], l=1 label [i] (the id).
@ mkds i n → *DataSet {
    : ( Vec f ) x ( vec_new [f] )
    : ( Vec f ) y ( vec_new [f] )
    : ~ i i2 0
    ~ < i2 n {
        ( vec_push [f] x # f i2 ) ( vec_push [f] x * 10.0 # f i2 )
        ( vec_push [f] y # f i2 )
        = i2 + i2 1
    }
    ^ ( data_new x y n 2 1 )
}

// Run a whole epoch, appending each emitted example's id (y[0]) to `ids`.
// Also asserts x[0] == id (feature/label stay aligned per row).
@ epoch_ids * DataLoader dl ( Vec i ) ids * u okal → v {
    : ( Vec f ) bx ( vec_new [f] )
    : ( Vec f ) by ( vec_new [f] )
    : ~ i rows ( dl_next dl bx by )
    ~ > rows 0 {
        : ~ i k 0
        ~ < k rows {
            : i id # i ( gf by k )
            ( vec_push [i] ids id )
            ? == # i ( gf bx * k 2 ) id {} { ( nurl_poke okal 0 0 ) }
            = k + k 1
        }
        = rows ( dl_next dl bx by )
    }
    ( vec_free [f] bx ) ( vec_free [f] by )
}

@ sorted_covers ( Vec i ) ids i n → b {
    ? == ( vec_len [i] ids ) n {} { ^ F }
    // mark-and-count: every id in [0,n) appears exactly once
    : ( Vec i ) seen ( vec_with_cap [i] n )
    : ~ i k 0
    ~ < k n { ( vec_push [i] seen 0 ) = k + k 1 }
    = k 0
    ~ < k ( vec_len [i] ids ) {
        : i id ( gi ids k )
        ? & >= id 0 < id n { ( vec_set [i] seen id + 1 ( gi seen id ) ) } { ^ F }
        = k + k 1
    }
    = k 0
    ~ < k n { ? == ( gi seen k ) 1 {} { ( vec_free [i] seen ) ^ F } = k + k 1 }
    ( vec_free [i] seen )
    ^ T
}

@ ids_eq ( Vec i ) a ( Vec i ) b → b {
    ? == ( vec_len [i] a ) ( vec_len [i] b ) {} { ^ F }
    : ~ i k 0
    ~ < k ( vec_len [i] a ) { ? == ( gi a k ) ( gi b k ) {} { ^ F } = k + k 1 }
    ^ T
}

@ main → i {
    : i N 10
    : *DataSet ds ( mkds N )
    : *u okal ( nurl_alloc 8 )
    ( nurl_poke okal 0 1 )

    // ── determinism + coverage (batch 3, no drop_last) ──
    : *DataLoader dl ( dl_new ds 3 F 42 )
    ( check == ( dl_num_batches dl ) 4 `num_batches = ceil(10/3) = 4` )
    : ( Vec i ) e1 ( vec_new [i] )
    ( epoch_ids dl e1 okal )
    ( check ( sorted_covers e1 N ) `epoch covers every example exactly once` )
    ( check == ( nurl_peek okal 0 ) 1 `features stay row-aligned with labels` )
    // reset with the SAME seed → identical order
    ( dl_reset dl 42 )
    : ( Vec i ) e2 ( vec_new [i] )
    ( epoch_ids dl e2 okal )
    ( check ( ids_eq e1 e2 ) `same seed → identical batch order` )
    // a shuffle actually happened (not the identity 0..9)
    : ~ b shuffled F
    : ~ i k 0
    ~ < k N { ? != ( gi e1 k ) k { = shuffled T } {} = k + k 1 }
    ( check shuffled `seeded order is a real permutation, not identity` )
    // different seed → different order (very likely)
    ( dl_reset dl 43 )
    : ( Vec i ) e3 ( vec_new [i] )
    ( epoch_ids dl e3 okal )
    ( check == ( ids_eq e1 e3 ) F `different seed → different order` )
    ( check ( sorted_covers e3 N ) `reshuffled epoch still covers once` )
    ( dl_free dl )

    // ── drop_last ──
    : *DataLoader dl2 ( dl_new ds 3 T 42 )
    ( check == ( dl_num_batches dl2 ) 3 `drop_last num_batches = floor(10/3) = 3` )
    : ( Vec i ) ed ( vec_new [i] )
    ( epoch_ids dl2 ed okal )
    ( check == ( vec_len [i] ed ) 9 `drop_last yields 9 rows (last partial dropped)` )
    ( dl_free dl2 )

    // ── no shuffle (seed <= 0) → identity order ──
    : *DataLoader dl3 ( dl_new ds 4 F 0 )
    : ( Vec i ) en ( vec_new [i] )
    ( epoch_ids dl3 en okal )
    : ~ b ident T
    = k 0
    ~ < k N { ? == ( gi en k ) k {} { = ident F } = k + k 1 }
    ( check ident `seed<=0 → identity (no shuffle)` )
    ( dl_free dl3 )

    // ── sharding: 3 shards partition [0,10) once ──
    : ( Vec i ) allsh ( vec_new [i] )
    : ~ i sh 0
    ~ < sh 3 {
        : *DataLoader dls ( dl_new_shard ds 2 F 0 3 sh )
        : ( Vec i ) es ( vec_new [i] )
        ( epoch_ids dls es okal )
        : ~ i j 0
        ~ < j ( vec_len [i] es ) { ( vec_push [i] allsh ( gi es j ) ) = j + j 1 }
        ( vec_free [i] es )
        ( dl_free dls )
        = sh + sh 1
    }
    ( check ( sorted_covers allsh N ) `3 shards partition the dataset exactly once` )
    ( vec_free [i] allsh )

    // ── streaming round-trip: streamed batches == in-memory batches ──
    : s ndfp `/tmp/nurl_data_test.ndf`
    : ~ b saveok F
    ?? ( data_save_ndf ndfp ds ) { T _ → { = saveok T } F e → { ( string_free e ) } }
    ( check saveok `dataset saves to .ndf` )
    // in-memory order for seed 7
    : *DataLoader dlm ( dl_new ds 3 F 7 )
    : ( Vec i ) mem ( vec_new [i] )
    ( epoch_ids dlm mem okal )
    ( dl_free dlm )
    ?? ( ndf_open ndfp ) {
        T st → {
            ( check & & == ( ndf_n st ) N == ( ndf_d st ) 2 == ( ndf_l st ) 1 `.ndf header round-trips (n/d/l)` )
            : *DataLoader dlst ( dl_stream st 3 F 7 )
            : ( Vec i ) strm ( vec_new [i] )
            ( epoch_ids dlst strm okal )
            ( check == ( nurl_peek okal 0 ) 1 `streamed rows stay feature/label-aligned` )
            ( check ( ids_eq mem strm ) `streamed batches == in-memory batches (same seed)` )
            ( check ( sorted_covers strm N ) `streamed epoch covers once` )
            ( vec_free [i] strm )
            ( dl_free dlst )
            ( ndf_close st )
        }
        F e → { ( nurl_print ( string_data e ) ) ( nurl_print `\n` ) ( string_free e ) = g_fail + g_fail 1 }
    }
    ( vec_free [i] mem )

    ( vec_free [i] e1 ) ( vec_free [i] e2 ) ( vec_free [i] e3 ) ( vec_free [i] ed ) ( vec_free [i] en )
    ( nurl_free okal )
    ( data_free ds )
    ( nurl_print `data_test: ` ) ( nurl_print_int g_pass )
    ( nurl_print ` passed, ` ) ( nurl_print_int g_fail ) ( nurl_print ` failed\n` )
    ^ ? > g_fail 0 1 0
}

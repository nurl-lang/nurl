// wal_test.nu — the write-ahead log.
//
//   NURL_STDLIB=<repo> ../../nurl.sh tests/wal_test.nu /tmp/wt && /tmp/wt
//
// Eight threads append 500 records each and wait for every one to be
// durable (group commit: far fewer writes than commits); replay finds all
// 4000, each intact and in LSN order; a torn tail (half a record) stops
// replay at the last intact record and truncation drops it; a log reset
// after a checkpoint starts at the LSN reached, never lower.

$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/pfile.nu`
$ `src/wal.nu`

: ~ i g_pass 0
: ~ i g_fail 0

@ check s what b ok → v {
    ? ok { = g_pass + g_pass 1 ( nurl_print `  ok ` ) } { = g_fail + g_fail 1 ( nurl_print `  FAIL ` ) }
    ( nurl_println what )
}

// A record: [u32 thread][u32 seq][seq bytes of filler].
@ rec_of i th i seq → ( Vec u ) {
    : ( Vec u ) r ( vec_zeroed [u] + 8 % seq 37 )
    : ( Slice u ) s ( slice_from_vec [u] r )
    ( slice_put_u32_le s 0 th )
    ( slice_put_u32_le s 4 seq )
    ^ r
}

@ main → i {
    : s path `/tmp/nurldb_wal_test.log`
    ?? ( file_delete path ) { T _ → {} F _ → {} }
    : Wal w ?? ( wal_open path T ) { T x → x F e → { ( nurl_println ( string_data e ) ) ^ 1 } }
    : Atomic bad ( atomic_new 0 )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 8 {
        : i me t
        : !Thread ThreadErr r ( thread_spawn \ → v {
            : ~ i k 0
            ~ < k 500 {
                : ( Vec u ) rec ( rec_of me k )
                : i lsn ( wal_append w ( slice_from_vec [u] rec ) )
                // Every tenth record is a "commit": it waits to be durable.
                ? == % k 10 0 {
                    ( wal_flush_to w lsn )
                    ? < ( wal_flushed w ) lsn { ( atomic_add bad 1 ) } {}
                } {}
                = k + k 1
            }
        } )
        ?? r { T th → { ( vec_push [Thread] ts th ) } F _ → {} }
        = t + t 1
    }
    ~ th ts { ( thread_join th ) }
    ( wal_flush_all w )
    : i end ( wal_next w )
    ( check `no commit returned before its record was durable` == ( atomic_load bad ) 0 )
    ( check `everything appended is durable` == ( wal_flushed w ) end )
    ( nurl_print `  (400 commits, ` ) ( nurl_print_int ( wal_writes w ) ) ( nurl_println ` log writes)` )
    ( check `group commit: fewer log writes than commits` < ( wal_writes w ) 400 )
    ( wal_close w )

    // Replay: every record, intact, in order; per thread in sequence.
    : ( Vec i ) seen ( vec_zeroed [i] 8 )
    : Atomic count ( atomic_new 0 )
    : Atomic order ( atomic_new 0 )
    : Atomic last ( atomic_new 0 )
    : i reached ?? ( wal_replay path 1 \ i lsn ( Slice u ) body → v {
        ( atomic_add count 1 )
        ? <= lsn ( atomic_load last ) { ( atomic_add order 1 ) } {}
        ( atomic_store last lsn )
        : i th ( slice_u32_le body 0 )
        : i seq ( slice_u32_le body 4 )
        ? != seq ( vec_at [i] seen th ) { ( atomic_add order 1 ) } {}
        ( vec_put [i] seen th + seq 1 )
    } ) { T x → x F _ → -1 }
    ( check `replay finds all 4000 records` == ( atomic_load count ) 4000 )
    ( check `in LSN order, each thread's in sequence` == ( atomic_load order ) 0 )
    ( check `replay reaches the log end` == reached end )

    // A torn tail: half a record past the end.
    : PFile pf ?? ( pfile_open path PFILE_RW ) { T h → h F _ → { ^ 1 } }
    : i size ?? ( pfile_size pf ) { T n → n F _ → 0 }
    : ( Vec u ) torn ( vec_zeroed [u] 12 )
    ( slice_put_u32_le ( slice_from_vec [u] torn ) 0 100 )
    ?? ( pfile_write_at pf ( slice_from_vec [u] torn ) size ) { T _ → {} F _ → {} }
    : i r2 ?? ( wal_replay path 1 \ i lsn ( Slice u ) body → v {} ) { T x → x F _ → -1 }
    ( check `a torn tail stops replay at the last intact record` == r2 end )
    ?? ( wal_truncate_to path r2 ) { T _ → {} F _ → {} }
    ( check `truncation drops the torn bytes` == ?? ( pfile_size pf ) { T n → n F _ → 0 } size )

    // Reset after a checkpoint: the next record's LSN continues from end.
    ?? ( wal_reset path end ) { T _ → {} F _ → {} }
    : Wal w2 ?? ( wal_open path T ) { T x → x F _ → { ^ 1 } }
    ( check `a reset log starts at the LSN it had reached` == ( wal_next w2 ) end )
    : ( Vec u ) one ( rec_of 9 9 )
    : i l2 ( wal_append w2 ( slice_from_vec [u] one ) )
    ( wal_flush_to w2 l2 )
    ( check `and grows from there` > l2 end )
    ( wal_close w2 )
    : Atomic c2 ( atomic_new 0 )
    : i r3 ?? ( wal_replay path end \ i lsn ( Slice u ) body → v { ( atomic_add c2 1 ) } ) { T x → x F _ → -1 }
    ( check `replay of the reset log finds the one record` & == ( atomic_load c2 ) 1 == r3 l2 )
    ?? ( file_delete path ) { T _ → {} F _ → {} }

    ( nurl_print `wal_test: ` ) ( nurl_print_int g_pass ) ( nurl_print ` passed, ` ) ( nurl_print_int g_fail ) ( nurl_println ` failed` )
    ^ ? == g_fail 0 0 1
}

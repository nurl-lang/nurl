// bufpool_test.nu — the buffer pool, under threads.
//
//   NURL_STDLIB=<repo> ../../nurl.sh tests/bufpool_test.nu /tmp/bt && /tmp/bt
//
// 200 pages through 32 frames (every pass evicts and writes back), then
// eight threads: six bump counters on random pages under write guards
// (each page holds its counter twice, at 64 and at 4096), two read random
// pages under read guards and count every page whose two copies differ —
// a torn page. Afterwards every counter is exactly what was added, the
// pages survive a flush and a fresh pool over the same file, and a page
// whose bytes were damaged on disk is refused, not served.

$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/rng.nu`
$ `stdlib/std/panic.nu`
$ `stdlib/std/pfile.nu`
$ `src/page.nu`
$ `src/wal.nu`
$ `src/bufpool.nu`

: ~ i g_pass 0
: ~ i g_fail 0

@ check s what b ok → v {
    ? ok { = g_pass + g_pass 1 ( nurl_print `  ok ` ) } { = g_fail + g_fail 1 ( nurl_print `  FAIL ` ) }
    ( nurl_println what )
}

: i NPAGES 200

@ bump BufPool p Wal w i pid → v {
    : PageWrite pw ( pool_write p pid )
    : ( Slice u ) b ( page_bytes_mut pw )
    : i c + ( slice_u64_le b 64 ) 1
    ( slice_put_u64_le b 64 c )
    ( slice_put_u64_le b 4096 c )
    // A change is logged first; the page carries its record's LSN.
    : ( Vec u ) rec ( vec_zeroed [u] 16 )
    ( slice_put_u64_le ( slice_from_vec [u] rec ) 0 pid )
    ( pg_set_lsn b ( wal_append w ( slice_from_vec [u] rec ) ) )
}

@ torn BufPool p i pid → b {
    : PageRead pr ( pool_read p pid )
    : ( Slice u ) b ( page_bytes pr )
    ^ != ( slice_u64_le b 64 ) ( slice_u64_le b 4096 )
}

@ counter BufPool p i pid → i {
    : PageRead pr ( pool_read p pid )
    ^ ( slice_u64_le ( page_bytes pr ) 64 )
}

@ main → i {
    : s dpath `/tmp/nurldb_bufpool_test.db`
    : s lpath `/tmp/nurldb_bufpool_test.log`
    ?? ( file_delete dpath ) { T _ → {} F _ → {} }
    ?? ( file_delete lpath ) { T _ → {} F _ → {} }
    : PFile df ?? ( pfile_open dpath PFILE_CREATE ) { T h → h F _ → { ^ 1 } }
    : Wal w ?? ( wal_open lpath F ) { T x → x F _ → { ^ 1 } }
    : BufPool p ( pool_new df w 32 )

    // 200 new pages through 32 frames.
    : ~ i k 0
    ~ < k NPAGES {
        : PageWrite pw ( pool_new_page p PT_HEAP )
        ? != ( page_write_pid pw ) k { ( nurl_println `  page numbers out of order` ) } {}
        = k + k 1
    }
    ( check `200 pages appended` == ( pool_npages p ) NPAGES )
    = k 0
    ~ < k NPAGES { ( bump p w k ) = k + k 1 }
    : ~ i ones 0
    = k 0
    ~ < k NPAGES { ? == ( counter p k ) 1 { = ones + ones 1 } {} = k + k 1 }
    ( check `every page read back after eviction` == ones NPAGES )
    ( check `evictions wrote dirty pages back` > ( pool_writes p ) 0 )

    // Eight threads.
    : Atomic torn_n ( atomic_new 0 )
    : Atomic bumps ( atomic_new 0 )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 8 {
        : i me t
        : !Thread ThreadErr r ( thread_spawn \ → v {
            : Rng g ( rng_seed + 1234 me )
            : ~ i j 0
            ~ < j 3000 {
                : i pid ( rng_below g NPAGES )
                ? < me 6 {
                    ( bump p w pid )
                    ( atomic_add bumps 1 )
                } {
                    ? ( torn p pid ) { ( atomic_add torn_n 1 ) } {}
                }
                = j + j 1
            }
        } )
        ?? r { T th → { ( vec_push [Thread] ts th ) } F _ → {} }
        = t + t 1
    }
    ~ th ts { ( thread_join th ) }
    ( check `no reader saw a torn page` == ( atomic_load torn_n ) 0 )
    : ~ i sum 0
    = k 0
    ~ < k NPAGES { = sum + sum ( counter p k ) = k + k 1 }
    ( check `every increment landed exactly once` == sum + NPAGES ( atomic_load bumps ) )
    ( nurl_print `  (hits ` ) ( nurl_print_int ( pool_hits p ) ) ( nurl_print `, misses ` ) ( nurl_print_int ( pool_misses p ) )
    ( nurl_print `, page writes ` ) ( nurl_print_int ( pool_writes p ) ) ( nurl_println `)` )

    // Flush, then a fresh pool over the same file sees the same pages.
    ( pool_flush_all p )
    ( check `nothing dirty after flush_all` == ( pool_dirty_count p ) 0 )
    ( check `the log is durable past every page written` >= ( wal_flushed w ) 0 )
    : BufPool p2 ( pool_new df w 16 )
    : ~ i sum2 0
    = k 0
    ~ < k NPAGES { = sum2 + sum2 ( counter p2 k ) = k + k 1 }
    ( check `a fresh pool reads the same counters from disk` == sum2 sum )

    // Damage one page on disk: reading it panics instead of serving it.
    : ( Vec u ) junk ( vec_zeroed [u] 8 )
    ( slice_put_u64_le ( slice_from_vec [u] junk ) 0 -1 )
    ?? ( pfile_write_at df ( slice_from_vec [u] junk ) + * 150 PAGE_SIZE 200 ) { T _ → {} F _ → {} }
    : BufPool p3 ( pool_new df w 16 )
    : !v PanicInfo pr ( recover \ → v { : i c ( counter p3 150 ) } )
    ( check `a damaged page is refused` ?? pr { T _ → F F _ → T } )
    ( check `and the pool still serves the others` == ( counter p3 151 ) ( counter p 151 ) )

    ( wal_close w )
    ?? ( file_delete dpath ) { T _ → {} F _ → {} }
    ?? ( file_delete lpath ) { T _ → {} F _ → {} }
    ( nurl_print `bufpool_test: ` ) ( nurl_print_int g_pass ) ( nurl_print ` passed, ` ) ( nurl_print_int g_fail ) ( nurl_println ` failed` )
    ^ ? == g_fail 0 0 1
}

// btree_test.nu — the B+tree, alone and under threads.
//
//   NURL_STDLIB=<repo> ../../nurl.sh tests/btree_test.nu /tmp/bt && /tmp/bt
//
// Keys encode in value order (negative numbers, reals, text with zero
// bytes and prefixes). 20 000 keys in random order come back sorted, a
// range scan returns exactly its range, deletes take keys out. Then eight
// threads insert 40 000 keys at once — splitting leaves, inner nodes and
// the root under each other — while two threads scan: every scan is in
// order, and afterwards every key is there once. Long text keys fill nodes
// with few entries (more splits, and compaction after deletes).

$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/rng.nu`
$ `stdlib/std/pfile.nu`
$ `src/page.nu`
$ `src/wal.nu`
$ `src/bufpool.nu`
$ `src/heap.nu`
$ `src/keys.nu`
$ `src/btree.nu`

: ~ i g_pass 0
: ~ i g_fail 0

@ check s what b ok → v {
    ? ok { = g_pass + g_pass 1 ( nurl_print `  ok ` ) } { = g_fail + g_fail 1 ( nurl_print `  FAIL ` ) }
    ( nurl_println what )
}

@ enc Value v i ty → ( Vec u ) {
    : ( Vec u ) out ( vec_new [u] )
    ( key_put out v ty )
    ^ out
}

@ before Value a Value b i ty → b {
    : ( Vec u ) ka ( enc a ty )
    : ( Vec u ) kb ( enc b ty )
    ^ < ( slice_bytes_cmp ( slice_from_vec [u] ka ) ( slice_from_vec [u] kb ) ) 0
}

@ int_key i x → ( Vec u ) { ^ ( int_key_tid x x ) }

// The key of INT `x` pointing at `tid`.
@ int_key_tid i x i tid → ( Vec u ) {
    : ( Vec Value ) row ( vec_new [Value] )
    ( vec_push [Value] row @ Value { VInt x } )
    : ( Vec i ) cols ( vec_new [i] )
    ( vec_push [i] cols 0 )
    : ( Vec i ) types ( vec_new [i] )
    ( vec_push [i] types TY_INT )
    ^ ( key_of_row row cols types tid )
}

// The INT a key holds (its first column), decoded back.
@ int_of_key ( Slice u ) k → i {
    : ~ i x 0
    : ~ i j 1
    ~ < j 9 { = x | << x 8 # i ( slice_byte k j ) = j + j 1 }
    ^ ^^ x MIN_I64
}

: Seen { i n i last b sorted }

// Scan the whole tree: how many keys, and whether they came in order.
@ scan_all Store st Index ix → Seen {
    : ( Vec u ) lo ( vec_zeroed [u] 1 )
    : ( Vec u ) hi ( vec_new [u] )
    : ~ i k 0
    ~ < k 32 { ( vec_push [u] hi # u 255 ) = k + k 1 }
    : ( Vec u ) prev ( vec_new [u] )
    : ~ i n 0
    : ~ b sorted T
    ( bt_scan st ix ( slice_from_vec [u] lo ) ( slice_from_vec [u] hi ) \ ( Slice u ) key → b {
        ? & > n 0 >= ( slice_bytes_cmp ( slice_from_vec [u] prev ) key ) 0 { = sorted F } {}
        ( vec_clear [u] prev )
        ( vec_extend_slice prev key )
        = n + n 1
        ^ T
    } )
    ^ @ Seen { n 0 sorted }
}

// Fisher-Yates.
@ shuffle Rng g ( Vec i ) v → v {
    : ~ i k - ( vec_len [i] v ) 1
    ~ > k 0 {
        : i j ( rng_below g + k 1 )
        : i t ( vec_at [i] v k )
        ( vec_put [i] v k ( vec_at [i] v j ) )
        ( vec_put [i] v j t )
        = k - k 1
    }
}

@ vec_extend_slice ( Vec u ) dst ( Slice u ) src → v {
    : ~ i k 0
    ~ < k ( slice_len [u] src ) { ( vec_push [u] dst # u ( slice_byte src k ) ) = k + k 1 }
}

@ root_level Store st Index ix → i {
    : PageRead r ( pool_read . st pool ( index_root ix ) )
    ^ ( bt_level ( page_bytes r ) )
}

@ new_index Store st i id → Index {
    : i anchor ( bt_create st )
    : ( Vec i ) cols ( vec_new [i] )
    ( vec_push [i] cols 0 )
    : ( Vec i ) types ( vec_new [i] )
    ( vec_push [i] types TY_INT )
    ^ ( index_new id 1 anchor ( bt_anchor_root st anchor ) cols types F )
}

@ main → i {
    : s dpath `/tmp/nurldb_btree_test.db`
    : s lpath `/tmp/nurldb_btree_test.log`
    ?? ( file_delete dpath ) { T _ → {} F _ → {} }
    ?? ( file_delete lpath ) { T _ → {} F _ → {} }
    : PFile df ?? ( pfile_open dpath PFILE_CREATE ) { T h → h F _ → { ^ 1 } }
    : Wal w ?? ( wal_open lpath F ) { T x → x F _ → { ^ 1 } }
    : Store st @ Store { ( pool_new df ( mem_dup w ) 64 ) ( mem_dup w ) }
    { : PageWrite meta ( pool_new_page . st pool PT_META ) }

    // ── key order ──
    ( check `ints order as numbers` & ( before @ Value { VInt -5 } @ Value { VInt 3 } TY_INT ) ( before @ Value { VInt -9000000000 } @ Value { VInt -5 } TY_INT ) )
    ( check `reals order as numbers` & ( before @ Value { VReal -2.5 } @ Value { VReal -1.0 } TY_REAL ) ( before @ Value { VReal 0.5 } @ Value { VReal 10.0 } TY_REAL ) )
    ( check `NULL sorts first` ( before @ Value { VNull } @ Value { VInt -9000000000 } TY_INT ) )
    ( check `a text sorts before what it prefixes` ( before @ Value { VText ( string_from `ab` ) } @ Value { VText ( string_from `abc` ) } TY_TEXT ) )
    ( check `text compares bytewise` ( before @ Value { VText ( string_from `abc` ) } @ Value { VText ( string_from `abd` ) } TY_TEXT ) )

    // ── one thread ──
    : Index ix ( new_index st 1 )
    : Rng g ( rng_seed 42 )
    : ( Vec i ) order ( vec_new [i] )
    : ~ i k 0
    ~ < k 20000 { ( vec_push [i] order k ) = k + k 1 }
    ( shuffle g order )
    ~ x order {
        : ( Vec u ) key ( int_key - x 10000 )
        ( bt_insert st ix ( slice_from_vec [u] key ) )
    }
    : Seen s1 ( scan_all st ix )
    ( check `20 000 keys in random order come back sorted` & == . s1 n 20000 . s1 sorted )
    ( check `the root split, and the anchor names the new one` & > ( root_level st ix ) 0 == ( index_root ix ) ( bt_anchor_root st ( index_anchor ix ) ) )
    : ~ i inrange 0
    : ~ b exact T
    : ( Vec u ) lo ( int_key_tid -100 0 )
    : ( Vec u ) hi ( int_key_tid 99 -1 )
    : ~ i expect -100
    ( bt_scan st ix ( slice_from_vec [u] lo ) ( slice_from_vec [u] hi ) \ ( Slice u ) key → b {
        ? != ( int_of_key key ) expect { = exact F } {}
        = expect + expect 1
        = inrange + inrange 1
        ^ T
    } )
    ( check `a range scan returns exactly [-100, 99]` & == inrange 200 exact )
    : ~ i gone 0
    = k 0
    ~ < k 20000 {
        : ( Vec u ) key ( int_key - k 10000 )
        ? ( bt_delete st ix ( slice_from_vec [u] key ) ) { = gone + gone 1 } {}
        = k + k 3
    }
    : Seen s2 ( scan_all st ix )
    ( check `deletes take their keys out` & == . s2 n - 20000 gone . s2 sorted )
    ( check `a key not there is not deleted` ! ( bt_delete st ix ( slice_from_vec [u] ( int_key 999999 ) ) ) )

    // ── eight writers, two readers ──
    : Index cx ( new_index st 2 )
    : Atomic writers ( atomic_new 8 )
    : Atomic scans ( atomic_new 0 )
    : Atomic unsorted ( atomic_new 0 )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 10 {
        : i me t
        : !Thread ThreadErr r ( thread_spawn \ → v {
            ? >= me 8 {
                ~ > ( atomic_load writers ) 0 {
                    : Seen sn ( scan_all st cx )
                    ? ! . sn sorted { ( atomic_add unsorted 1 ) } {}
                    ( atomic_add scans 1 )
                }
                ^
            } {}
            : Rng rg ( rng_seed + 7 me )
            : ( Vec i ) mine ( vec_new [i] )
            : ~ i j 0
            ~ < j 5000 { ( vec_push [i] mine + * j 8 me ) = j + j 1 }
            ( shuffle rg mine )
            ~ x mine {
                : ( Vec u ) key ( int_key x )
                ( bt_insert st cx ( slice_from_vec [u] key ) )
            }
            ( atomic_sub writers 1 )
        } )
        ?? r { T h → { ( vec_push [Thread] ts h ) } F _ → {} }
        = t + t 1
    }
    ~ h ts { ( thread_join h ) }
    : Seen s3 ( scan_all st cx )
    ( check `40 000 keys from eight threads, each once, in order` & == . s3 n 40000 . s3 sorted )
    ( check `no concurrent scan saw keys out of order` == ( atomic_load unsorted ) 0 )
    ( check `the readers scanned while the writers split` > ( atomic_load scans ) 0 )
    : ~ i missing 0
    = k 0
    ~ < k 40000 {
        : ( Vec u ) klo ( int_key k )
        : ~ b found F
        ( bt_scan st cx ( slice_from_vec [u] klo ) ( slice_from_vec [u] klo ) \ ( Slice u ) key → b { = found T ^ F } )
        ? ! found { = missing + missing 1 } {}
        = k + k 97
    }
    ( check `point lookups find sampled keys` == missing 0 )
    ( nurl_print `  (` ) ( nurl_print_int ( atomic_load scans ) ) ( nurl_print ` concurrent scans, pages ` ) ( nurl_print_int ( pool_npages . st pool ) ) ( nurl_println `)` )

    // ── long keys ──
    : i anchor3 ( bt_create st )
    : ( Vec i ) tcols ( vec_new [i] )
    ( vec_push [i] tcols 0 )
    : ( Vec i ) ttypes ( vec_new [i] )
    ( vec_push [i] ttypes TY_TEXT )
    : Index tx ( index_new 3 1 anchor3 ( bt_anchor_root st anchor3 ) tcols ttypes F )
    = k 0
    ~ < k 600 {
        : String sv ( string_new )
        : ~ i r 0
        ~ < r + 50 % * k 37 900 { ( string_push_char sv + 97 % + k r 26 ) = r + r 1 }
        : ( Vec Value ) row ( vec_new [Value] )
        ( vec_push [Value] row @ Value { VText sv } )
        : ( Vec u ) key ( key_of_row row tcols ttypes k )
        ( bt_insert st tx ( slice_from_vec [u] key ) )
        = k + k 1
    }
    : Seen s4 ( scan_all st tx )
    ( check `600 text keys up to 950 bytes, sorted` & == . s4 n 600 . s4 sorted )

    ( pool_flush_all . st pool )
    ( wal_close w )
    ?? ( file_delete dpath ) { T _ → {} F _ → {} }
    ?? ( file_delete lpath ) { T _ → {} F _ → {} }
    ( nurl_print `btree_test: ` ) ( nurl_print_int g_pass ) ( nurl_print ` passed, ` ) ( nurl_print_int g_fail ) ( nurl_println ` failed` )
    ^ ? == g_fail 0 0 1
}

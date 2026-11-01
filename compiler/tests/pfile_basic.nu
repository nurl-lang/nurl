// pfile_basic.nu — std/pfile.nu acceptance.
//
// One thread: write at offsets past the end (the gap reads as zeros), read
// back into a window of a larger buffer, a read across the end comes back
// short and read_exact says UnexpectedEof, set_len cuts the file, and a
// fresh-Vec read takes only what is there. Then four threads share one
// handle: each writes its own 64 blocks of 512 bytes at interleaved
// offsets and reads every block back — no thread's position can move
// another's — and the whole file is checked from a fifth handle.
// requires: live

$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/pfile.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/core/string.nu`

// `name` under the platform's temp directory (env_temp_dir).
@ tmp_path s name → String {
    : String p ( env_temp_dir )
    ( string_push_char p 47 )
    ( string_push_str p name )
    ^ p
}

@ show s label i x → v { ( nurl_print label ) ( nurl_println_int x ) }

@ bytes_of s text → ( Vec u ) {
    : ( Slice u ) b ( slice_of_str text )
    ^ ( slice_to_vec [u] b )
}

@ main → i {
    // Scratch paths under the platform's temp directory: on Windows /tmp
    // is a directory on the current drive that exists only if something
    // made it first (agora #306).
    : String tp0 ( tmp_path `nurl_pfile_basic.dat` )
    : s path ( string_data tp0 )
    : PFile f ?? ( pfile_open path PFILE_TRUNC ) { T h → h F _ → { ( nurl_println `open failed` ) ^ 1 } }
    : ( Vec u ) hello ( bytes_of `hello` )
    : ( Vec u ) world ( bytes_of `world` )
    ?? ( pfile_write_at f ( slice_from_vec [u] hello ) 0 ) { T _ → {} F _ → { ( nurl_println `write 1 failed` ) } }
    ?? ( pfile_write_at f ( slice_from_vec [u] world ) 10 ) { T _ → {} F _ → { ( nurl_println `write 2 failed` ) } }
    ( show `size:        ` ?? ( pfile_size f ) { T n → n F _ → -1 } )

    // Into a window of a bigger buffer.
    : ( Vec u ) buf ( vec_zeroed [u] 32 )
    : ( Slice u ) win ( slice_window [u] ( slice_from_vec [u] buf ) 4 15 )
    ( show `read:        ` ?? ( pfile_read_at f win 0 ) { T n → n F _ → -1 } )
    ( show `byte 4 (h):  ` ( vec_at [u] buf 4 ) )
    ( show `gap byte:    ` ( vec_at [u] buf 9 ) )
    ( show `byte 14 (w): ` ( vec_at [u] buf 14 ) )

    // Across the end: short, and exact says so.
    : ( Vec u ) tail ( vec_zeroed [u] 10 )
    ( show `short read:  ` ?? ( pfile_read_at f ( slice_from_vec [u] tail ) 10 ) { T n → n F _ → -1 } )
    ?? ( pfile_read_exact_at f ( slice_from_vec [u] tail ) 10 ) {
        T _ → { ( show `exact:       ` 0 ) }
        F e → { ( show `exact eof:   ` ?? e { UnexpectedEof → 1 _ → 0 } ) }
    }
    ?? ( pfile_set_len f 3 ) { T _ → {} F _ → { ( nurl_println `set_len failed` ) } }
    : ( Vec u ) rest ?? ( pfile_read_vec_at f 0 100 ) { T v → v F _ → ( vec_new [u] ) }
    ( show `after cut:   ` ( vec_len [u] rest ) )
    ?? ( pfile_sync f ) { T _ → {} F _ → { ( nurl_println `sync failed` ) } }
    ?? ( pfile_datasync f ) { T _ → {} F _ → { ( nurl_println `datasync failed` ) } }

    // Four threads, one handle, interleaved blocks.
    ?? ( pfile_set_len f 0 ) { T _ → {} F _ → {} }
    : Atomic bad ( atomic_new 0 )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 4 {
        : i me t
        : !Thread ThreadErr r ( thread_spawn \ → v {
            : ( Vec u ) blk ( vec_zeroed [u] 512 )
            : ( Slice u ) bs ( slice_from_vec [u] blk )
            : ~ i k 0
            ~ < k 64 {
                : i no + * k 4 me
                ( slice_put [u] bs 0 me )
                ( slice_put [u] bs 511 & no 255 )
                ?? ( pfile_write_at f bs * no 512 ) { T _ → {} F _ → { ( atomic_add bad 1 ) } }
                = k + k 1
            }
            = k 0
            : ( Vec u ) back ( vec_zeroed [u] 512 )
            ~ < k 64 {
                : i no + * k 4 me
                ?? ( pfile_read_exact_at f ( slice_from_vec [u] back ) * no 512 ) {
                    T _ → { ? | != # i ( vec_at [u] back 0 ) me != # i ( vec_at [u] back 511 ) & no 255 { ( atomic_add bad 1 ) } {} }
                    F _ → { ( atomic_add bad 1 ) }
                }
                = k + k 1
            }
        } )
        ?? r { T th → { ( vec_push [Thread] ts th ) } F _ → {} }
        = t + t 1
    }
    ~ th ts { ( thread_join th ) }
    ( show `thread errors: ` ( atomic_load bad ) )
    : PFile g ?? ( pfile_open path PFILE_READ ) { T h → h F _ → { ( nurl_println `reopen failed` ) ^ 1 } }
    ( show `final size:    ` ?? ( pfile_size g ) { T n → n F _ → -1 } )
    : ( Vec u ) all ?? ( pfile_read_vec_at g 0 131072 ) { T v → v F _ → ( vec_new [u] ) }
    : ~ i wrong 0
    : ~ i no 0
    ~ < no 256 {
        ? | != # i ( vec_at [u] all * no 512 ) % no 4 != # i ( vec_at [u] all + * no 512 511 ) & no 255 { = wrong + wrong 1 } {}
        = no + no 1
    }
    ( show `wrong blocks:  ` wrong )
    ( file_delete path )
    ^ 0
}

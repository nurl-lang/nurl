// kvcheck.nu — the KV-cache eviction bookkeeping, against a replay of
// the reference's own eviction code.
//
// Runs in a second. Checking this against the model itself would need
// 73+ frames through a 909M-parameter transformer on both sides, which
// is hours; this checks the thing that actually differs — which frames
// stay live and how many rows that is.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`
$ `deps/gpukit/src/devops.nu`
$ `src/weights.nu`
$ `src/devblock.nu`
$ `src/load.nu`
$ `src/dino.nu`
$ `src/aggregator.nu`

: i KV_P 783
: i KV_FRAMES 120

@ row s label i n → v {
    ( nurl_print label ) ( nurl_print ` ` )
    ( nurl_print ( nurl_str_int n ) ) ( nurl_print ` |` )
}

@ main → i {
    // frames held in full: the two full-frame regions, capped by how
    // many frames there have been
    ( row `kv_frames` KV_FRAMES )
    : ~ i f 0
    ~ < f KV_FRAMES {
        : i ns ( ag_kv_evicted f )
        : i full ? == ns 0 + f 1 - + f 1 ns
        ( nurl_print ` ` ) ( nurl_print ( nurl_str_int full ) )
        = f + f 1
    }
    ( nurl_print `\n` )

    ( row `kv_specials` KV_FRAMES )
    = f 0
    ~ < f KV_FRAMES {
        ( nurl_print ` ` ) ( nurl_print ( nurl_str_int ( ag_kv_evicted f ) ) )
        = f + f 1
    }
    ( nurl_print `\n` )

    ( row `kv_live` KV_FRAMES )
    = f 0
    ~ < f KV_FRAMES {
        ( nurl_print ` ` ) ( nurl_print ( nurl_str_int ( ag_kv_nvalid f KV_P ) ) )
        = f + f 1
    }
    ( nurl_print `\n` )

    ( row `kv_rows` 1 )
    ( nurl_print ` ` )
    ( nurl_print ( nurl_str_int ( ag_kv_rows KV_FRAMES KV_P ) ) )
    ( nurl_print `\n` )

    // Every frame must land inside the cache it was allocated for, and
    // the six rows it displaces must land somewhere else entirely.
    : i cap ( ag_kv_rows KV_FRAMES KV_P )
    : ~ i badw 0
    : ~ i bade 0
    = f 0
    ~ < f KV_FRAMES {
        : i wo ( ag_kv_woff f KV_P )
        ? > + wo KV_P ( ag_kv_nvalid f KV_P ) { = badw + badw 1 } {}
        ? > + wo KV_P cap { = badw + badw 1 } {}
        : i ns ( ag_kv_evicted f )
        ? > ns 0 {
            : i dst + + * AG_KV_SCALE KV_P * ( ag_kv_ring ) KV_P * - ns 1 AG_SPECIAL
            // the preserved rows go past every full-frame slot, and stay
            // inside what the cache was allocated for
            ? < dst + * AG_KV_SCALE KV_P * ( ag_kv_ring ) KV_P { = bade + bade 1 } {}
            ? > + dst AG_SPECIAL cap { = bade + bade 1 } {}
            ? > + dst AG_SPECIAL ( ag_kv_nvalid f KV_P ) { = bade + bade 1 } {}
        } {}
        = f + f 1
    }
    ( nurl_print `kv_bad 2 | ` ) ( nurl_print ( nurl_str_int badw ) )
    ( nurl_print ` ` ) ( nurl_print ( nurl_str_int bade ) ) ( nurl_print `\n` )
    ^ 0
}

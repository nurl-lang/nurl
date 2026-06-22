// http2_hpack_bomb.nu — regression for the HPACK decompression bomb
// (decompression amplification, the HPACK analogue of a zip bomb).
//
// HPACK lets a peer insert ONE large entry into the dynamic table with a
// literal-with-incremental-indexing field, then reference it again and
// again with 1-byte indexed fields. A few KiB of such references expands
// to hundreds of MiB of decoded headers — `hpack_decode_block` used to
// materialise every one of them into the result Vec with no ceiling.
//
// This builds exactly that shape: a ~4 KiB dynamic entry followed by 600
// one-byte references to it (≈ 4.6 KiB encoded → ≈ 2.4 MiB decoded), and
// asserts the decoder now aborts with HpackListTooLarge once the cumulative
// decoded size crosses hpack_max_decoded_bytes (2 MiB) instead of running
// the allocation to completion. main returns the failure count (0 = pass).

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/ext/http2_hpack.nu`

// HPACK integer with an N-bit prefix where 2^N-1 == `prefix_max`
// (RFC 7541 §5.1). We only ever encode string lengths here, so the
// high prefix bits (the H flag) are left clear.
@ enc_int ( Vec u ) out i prefix_max i value → v {
    ? < value prefix_max {
        ( vec_push [u] out # u value )
    } {
        ( vec_push [u] out # u prefix_max )
        : ~ i v - value prefix_max
        ~ >= v 128 {
            ( vec_push [u] out # u | & v 127 128 )
            = v / v 128
        }
        ( vec_push [u] out # u v )
    }
}

@ run → i {
    : ~ i fails 0
    : i vlen 4000  // dyn-table entry: name(1) + value(4000) + 32 = 4033 ≤ 4096

    : ( Vec u ) blk ( vec_new [u] )
    // Field 1: literal with incremental indexing, new name (0x40).
    ( vec_push [u] blk # u 0x40 )
    ( enc_int blk 127 1 )  // name length = 1
    ( vec_push [u] blk # u 0x78 )  // 'x'
    ( enc_int blk 127 vlen )  // value length
    : ~ i k 0
    ~ < k vlen {
        ( vec_push [u] blk # u 0x61 )  // 'a'
        = k + k 1
    }
    // 600 one-byte indexed references to dynamic index 62 (0x80 | 62 =
    // 0xBE) — the entry just inserted. ≈ 2.4 MiB decoded, past the cap.
    : ~ i r 0
    ~ < r 600 {
        ( vec_push [u] blk # u 0xBE )
        = r + r 1
    }

    : HpackDynTable dyn ( hpack_dyn_new 4096 )
    : !HpackDecoded HpackErr res ( hpack_decode_block blk dyn )
    ?? res {
        T dd → {
            // Bomb was fully decoded — the guard failed.
            ( nurl_eprintln `FAIL: HPACK bomb decoded without hitting the cap` )
            = fails + fails 1
            ( vec_free_with [Header] . dd headers \ Header h → v { ( header_free h ) } )
        }
        F e → {
            : s nm ( hpack_err_name e )
            ? != 0 ( nurl_str_eq nm `HpackListTooLarge` ) {
                ( puts `ok: HPACK bomb rejected with HpackListTooLarge` )
            } {
                ( nurl_eprintln ( nurl_str_cat `FAIL: wrong HPACK error: ` nm ) )
                = fails + fails 1
            }
        }
    }
    ( hpack_dyn_free dyn )
    ( vec_free [u] blk )
    ^ fails
}

@ main → i {
    ^ ( run )
}

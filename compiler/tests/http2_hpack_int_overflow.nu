// http2_hpack_int_overflow.nu — regression for the HPACK integer-overflow
// remote crash. hpack_decode_int accumulated continuation bytes with no
// ceiling on `value`, only a shift>63 guard. Input 0xFF followed by nine
// 0x7F/0xFF continuation bytes wrapped `value` negative; a negative length
// then flowed into hpack_decode_string → __hpack_huffman_decode and was
// dereferenced at a wild offset (SIGSEGV), reachable pre-auth from an ~11
// byte HEADERS payload.
//
// The fix caps the accumulator at hpack_max_int before consuming the next
// byte, so the bomb is rejected as HpackIntegerOverflow. This test feeds
// the exact shape through both the raw integer decoder and the full block
// decoder and asserts a clean error (not a crash, not a negative length).
// Offline — no sockets. main returns the failure count (0 = pass).

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/ext/http2_hpack.nu`

@ push_bytes ( Vec u ) v ( Vec i ) bs → v {
    : ~ i k 0
    ~ < k ( vec_len [i] bs ) {
        ( vec_push [u] v # u ( __ri bs k ) )
        = k + k 1
    }
}

@ __ri ( Vec i ) v i k → i {
    : ?i g ( vec_get [i] v k )
    ?? g { T x → { ^ x } F _ → { ^ 0 } }
}

@ run → i {
    : ~ i fails 0

    // 1) Raw integer decode: prefix byte 0xFF (all prefix bits set, so the
    //    value continues), then ten 0xFF continuation bytes. This is the
    //    classic overflow bomb; it must be HpackIntegerOverflow.
    : ( Vec u ) ib ( vec_new [u] )
    ( vec_push [u] ib # u 0xFF )
    : ~ i c 0
    ~ < c 10 { ( vec_push [u] ib # u 0xFF ) = c + c 1 }
    : !HpackInt HpackErr ir ( hpack_decode_int ib 0 7 )
    ?? ir {
        T iv → {
            ( nurl_print `  FAIL int-bomb accepted, value=` )
            ( nurl_print ( nurl_str_int . iv value ) )
            ( nurl_print `\n` )
            = fails + fails 1
        }
        F e → {
            ? != 0 ( nurl_str_eq ( hpack_err_name e ) `HpackIntegerOverflow` ) {
                ( nurl_print `  ok   int-bomb rejected: HpackIntegerOverflow\n` )
            } {
                ( nurl_print `  FAIL int-bomb wrong error: ` )
                ( nurl_print ( hpack_err_name e ) )
                ( nurl_print `\n` )
                = fails + fails 1
            }
        }
    }
    ( vec_free [u] ib )

    // 2) Full block decode of a literal-with-incremental-indexing field
    //    (0x40) whose NAME length is the overflow bomb. Before the fix the
    //    negative length reached the string decoder and dereferenced a wild
    //    pointer. Now the block decode must surface a clean HpackErr.
    : ( Vec u ) blk ( vec_new [u] )
    ( vec_push [u] blk # u 0x40 )  // literal, incremental indexing, new name
    ( vec_push [u] blk # u 0x7F )  // name length: 7-bit prefix all-ones → continue
    : ~ i c2 0
    ~ < c2 10 { ( vec_push [u] blk # u 0xFF ) = c2 + c2 1 }
    ( vec_push [u] blk # u 0x00 )  // final continuation byte

    : HpackDynTable dyn ( hpack_dyn_new 4096 )
    : !HpackDecoded HpackErr br ( hpack_decode_block blk dyn )
    ?? br {
        T dec → {
            ( nurl_print `  FAIL block-bomb decoded instead of erroring\n` )
            ( hpack_decoded_free dec )
            = fails + fails 1
        }
        F e → {
            ( nurl_print `  ok   block-bomb rejected: ` )
            ( nurl_print ( hpack_err_name e ) )
            ( nurl_print `\n` )
        }
    }
    ( hpack_dyn_free dyn )
    ( vec_free [u] blk )

    ? == fails 0 {
        ( nurl_print `hpack integer-overflow defended\n` )
    } {}
    ^ fails
}

@ main → i { ^ ( run ) }

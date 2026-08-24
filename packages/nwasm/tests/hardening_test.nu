// packages/nwasm/tests/hardening_test.nu — hostile-input regression tests.
//
// Every module below is malformed in a way that, before the hardening pass,
// either hung the decoder (unbounded / backward cursor loop) or drove an
// unbounded allocation from an attacker-chosen count. Each must now be
// REJECTED cleanly (module.ok = false) and — critically — return here, i.e.
// the decoder terminates instead of spinning. These are the decode-time
// counterparts of the fuzz + truncation sweep that produced zero hangs.
//
//   NURL_STDLIB=<repo> ../../nurl.sh tests/hardening_test.nu /tmp/ht && /tmp/ht

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `src/module.nu`

: ~ i g_fail 0

// Decode `hex` and assert the module is rejected (ok = false). Reaching this
// assertion at all proves the decoder terminated on the hostile input.
@ ck_reject s label s hex → v {
    ( nurl_print label )
    : !( Vec u ) ParseErr dr ( bytes_from_hex hex )
    ?? dr {
        T bytes → {
            : *Module m ( module_decode bytes )
            ? . m ok {
                ( nurl_print ` UNEXPECTEDLY ACCEPTED\n` ) = g_fail + g_fail 1
            } {
                : String es ( bytes_to_str . m err )
                ( nurl_print ` rejected: ` ) ( nurl_print ( string_data es ) ) ( nurl_print `\n` )
                ( string_free es )
            }
            ( module_free m )
        }
        F → { ( nurl_print ` (hex parse failed)\n` ) = g_fail + g_fail 1 }
    }
}

@ main → i {
    // Over-long section size: a 10-byte LEB with the high bit set decodes to a
    // negative i64. Unguarded, `pos + size` lands before pos → infinite loop.
    ( ck_reject `overlong section size: ` `0061736d0100000001ffffffffffffffffff7f` )
    // Count far exceeding the bytes that remain (unbounded allocation seed).
    ( ck_reject `huge type count:       ` `0061736d010000000102ff7f` )
    // Constant init expression truncated before its terminating 0x0b `end`.
    ( ck_reject `truncated const expr:  ` `0061736d010000000605017f004100` )
    // Declared memory minimum past the wasm32 4 GiB / 65536-page ceiling.
    ( ck_reject `memory min over limit: ` `0061736d0100000005050100f0a204` )
    // Data-segment byte length larger than the whole module.
    ( ck_reject `huge data seg length:  ` `0061736d010000000b04010041000bffffffff0f` )
    // A local run whose count is 2^63-1, declared after a run that already
    // pushed one local: `locals_so_far + count` wraps to a negative and slips
    // past a ceiling test written as a sum, leaving a 2^63-iteration push loop.
    ( ck_reject `overflowing local run: ` `0061736d01000000010401600000030201000a10010e02017fffffffffffffffff7f7f0b` )
    // Active data segment running past the declared initial memory: 10 bytes
    // at offset 65530 of a one-page memory.
    ( ck_reject `data seg past memory:  ` `0061736d0100000005030100010b12010041faff030b0a00000000000000000000` )

    ? == g_fail 0 { ( nurl_print `all hardening tests passed\n` ) ^ 0 } {}
    ( nurl_print `HARDENING FAILURES: ` ) ( nurl_print_int g_fail ) ( nurl_print `\n` )
    ^ 1
}

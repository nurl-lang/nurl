// packages/swarm-mcp/tests/blob_test.nu — the content-addressed data layer.
// Manifest determinism, hex addressing, cache store/append with corruption
// rejection, the HMAC-tagged seed handler, and the v4 payload round-trip.
// Run from the package root:
//   NURL_STDLIB=<repo> ../../nurl.sh tests/blob_test.nu /tmp/bt && /tmp/bt

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `src/token.nu`
$ `src/blob.nu`
$ `src/wasmkernel.nu`

: ~ i g_fail 0

@ check b cond s name → v {
    ? cond { ( nurl_print `  ok  ` ) } { ( nurl_print `  FAIL ` ) = g_fail + g_fail 1 }
    ( nurl_print name ) ( nurl_print `\n` )
}

// A deterministic pseudo-random byte vector.
@ mkbytes i n i seed → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] n )
    : ~ i s seed
    : ~ i k 0
    ~ < k n {
        = s + * s 6364136223846793005 1442695040888963407
        ( vec_push [u] v # u & >> s 33 255 )
        = k + k 1
    }
    ^ v
}

@ main → i {
    // ── manifest ─────────────────────────────────────────────────────
    : i bb * ( blob_block_vals ) 8
    : ( Vec u ) data ( mkbytes + bb 4096 7 )  // one full block + a short tail
    : ( Vec ( Vec u ) ) m1 ( blob_manifest data )
    : ( Vec ( Vec u ) ) m2 ( blob_manifest data )
    ( check == ( vec_len [( Vec u )] m1 ) 2 `manifest: 8 MiB + tail → 2 blocks` )
    : ( Vec u ) h0 ?? ( vec_get [( Vec u )] m1 0 ) { T x → x F → ( vec_new [u] ) }
    : ( Vec u ) h0b ?? ( vec_get [( Vec u )] m2 0 ) { T x → x F → ( vec_new [u] ) }
    : ( Vec u ) h1 ?? ( vec_get [( Vec u )] m1 1 ) { T x → x F → ( vec_new [u] ) }
    ( check == ( vec_len [u] h0 ) 32 `manifest: 32-byte hashes` )
    ( check ( bytes_eq h0 h0b ) `manifest: deterministic` )
    ( check ! ( bytes_eq h0 h1 ) `manifest: distinct blocks differ` )
    : String hx ( blob_hex h0 )
    ( check == ( string_len hx ) 64 `hex: 64 chars` )
    ( string_free hx )

    // ── cache store / append / corruption ────────────────────────────
    : ( Vec u ) small ( mkbytes 4096 42 )
    : ( Vec u ) sh ( blob_hash small )
    ( check ( blob_store sh small ) `store: verified write` )
    ( check ( blob_cached sh ) `store: cached afterwards` )
    : ( Vec u ) out ( vec_new [u] )
    ( check ( blob_append sh out ) `append: cache hit` )
    ( check ( bytes_eq out small ) `append: bytes intact` )
    : ( Vec u ) wrong ( mkbytes 4096 43 )
    ( check ! ( blob_store sh wrong ) `store: wrong bytes for a hash REJECTED` )
    : ( Vec u ) missing ( blob_hash wrong )
    : ( Vec u ) out2 ( vec_new [u] )
    ( check ! ( blob_append missing out2 ) `append: miss reported` )
    ( vec_free [u] out ) ( vec_free [u] out2 ) ( vec_free [u] wrong ) ( vec_free [u] missing )

    // ── the seed handler (HMAC round-trip) ───────────────────────────
    : ( Vec u ) key ( token_key `blob-test-token` )
    : ( @ ( Vec u ) ( Vec u ) ) h ( blob_handler key )
    : ( Vec u ) small2 ( mkbytes 2048 99 )
    : ( Vec u ) sh2 ( blob_hash small2 )
    : ( Vec u ) sp ( blob_seed_payload sh2 small2 )
    : ( Vec u ) tagged ( token_tag key sp )
    : ( Vec u ) r ( h tagged )
    : ~ i seed_ok 0
    ?? ( token_untag key r ) {
        T body → { = seed_ok ?? ( vec_get [u] body 0 ) { T x → # i x F → 0 } ( vec_free [u] body ) }
        F → {}
    }
    ( check == seed_ok 1 `seed handler: ok result` )
    ( check ( blob_cached sh2 ) `seed handler: block cached` )
    // forged tag → ok=0
    : ( Vec u ) badkey ( token_key `wrong-token` )
    : ( Vec u ) forged ( token_tag badkey sp )
    : ( Vec u ) r2 ( h forged )
    : ~ i forged_ok 1
    ?? ( token_untag key r2 ) {
        T body → { = forged_ok ?? ( vec_get [u] body 0 ) { T x → # i x F → 0 } ( vec_free [u] body ) }
        F → {}
    }
    ( check == forged_ok 0 `seed handler: forged payload rejected` )
    ( vec_free [u] sp ) ( vec_free [u] tagged ) ( vec_free [u] r )
    ( vec_free [u] forged ) ( vec_free [u] r2 ) ( vec_free [u] badkey )
    ( vec_free [u] small2 ) ( vec_free [u] sh2 )

    // ── payload v4 round-trip ────────────────────────────────────────
    : ( Vec i ) params ( vec_new [i] )
    ( vec_push [i] params 4650000000000000000 )
    : ( Vec ( Vec u ) ) hashes ( vec_new [( Vec u )] )
    ( vec_push [( Vec u )] hashes ( blob_hash small ) )
    ( vec_push [( Vec u )] hashes ( blob_hash data ) )
    : ( Vec u ) wasm ( mkbytes 512 5 )
    // dtype (1 = f64) rides in byte 1's high nibble — the argument this call
    // used to omit, which silently shifted `hashes`/`wasm` one slot left.
    : ( Vec u ) p4 ( wasm_gpu_chunk_payload_blobs 0 1000 3000 0 params 7 1 hashes wasm )
    : GpuChunk c ( wasm_gpu_chunk_decode p4 )
    ( check == . c ok 1 `v4: decodes` )
    ( check & == . c lo 1000 == . c hi 3000 `v4: range` )
    ( check == . c b0 7 `v4: first block index` )
    ( check == . c dtype 1 `v4: dataset dtype` )
    ( check == ( vec_len [( Vec u )] . c blobs ) 2 `v4: 2 block hashes` )
    : ( Vec u ) ch0 ?? ( vec_get [( Vec u )] . c blobs 0 ) { T x → x F → ( vec_new [u] ) }
    : ( Vec u ) eh0 ?? ( vec_get [( Vec u )] hashes 0 ) { T x → x F → ( vec_new [u] ) }
    ( check ( bytes_eq ch0 eh0 ) `v4: hash bytes intact` )
    ( check == ( vec_len [i] . c params ) 1 `v4: params carried` )
    ( check ( bytes_eq . c wasm wasm ) `v4: module bytes intact` )
    // truncated frame must not decode
    : ( Vec u ) trunc ( bytes_slice p4 0 30 )
    : GpuChunk ct ( wasm_gpu_chunk_decode trunc )
    ( check == . ct ok 0 `v4: truncated frame rejected` )
    ( gpu_chunk_free ct )
    ( vec_free [u] trunc )
    ( gpu_chunk_free c )
    ( blob_manifest_free hashes )
    ( vec_free [u] p4 ) ( vec_free [u] wasm ) ( vec_free [i] params )

    // ── v4 slice assembly from the cache ─────────────────────────────
    // two cached 4 KiB "blocks" cannot be real 8 MiB grid blocks, so test
    // the arithmetic with block 0 only: cache `small` (4096 B = 512 vals)
    // and assemble lo=8..hi=200 relative to b0=0.
    : ( Vec i ) nop ( vec_new [i] )
    : ( Vec ( Vec u ) ) ah ( vec_new [( Vec u )] )
    ( vec_push [( Vec u )] ah ( blob_hash small ) )
    : ( Vec u ) aw ( mkbytes 64 3 )
    : ( Vec u ) ap ( wasm_gpu_chunk_payload_blobs 0 8 200 0 nop 0 1 ah aw )
    : ~ GpuChunk ac ( wasm_gpu_chunk_decode ap )
    ( check ( gpu_chunk_assemble ac ) `assemble: cached block ok` )
    ( check == ( vec_len [u] . ac data ) * 8 192 `assemble: exact take (8·(hi−lo))` )
    : ( Vec u ) expect ( bytes_slice small 64 1600 )
    ( check ( bytes_eq . ac data expect ) `assemble: correct window (skip honoured)` )
    ( vec_free [u] expect )
    ( gpu_chunk_free ac )
    // a chunk referencing an uncached hash must fail
    : ( Vec ( Vec u ) ) mh ( vec_new [( Vec u )] )
    : ( Vec u ) ghost ( mkbytes 100 77 )
    ( vec_push [( Vec u )] mh ( blob_hash ghost ) )
    : ( Vec u ) mp ( wasm_gpu_chunk_payload_blobs 0 0 10 0 nop 0 1 mh aw )
    : ~ GpuChunk mc ( wasm_gpu_chunk_decode mp )
    ( check ! ( gpu_chunk_assemble mc ) `assemble: missing block FAILS the chunk` )
    ( gpu_chunk_free mc )
    ( vec_free [u] ghost ) ( vec_free [u] mp )
    ( blob_manifest_free mh )
    ( blob_manifest_free ah )
    ( vec_free [u] ap ) ( vec_free [u] aw ) ( vec_free [i] nop )

    ( vec_free [u] small ) ( vec_free [u] sh )
    ( blob_manifest_free m1 ) ( blob_manifest_free m2 )
    ( vec_free [u] data ) ( vec_free [u] key )
    // the handler closure's env is manual (factory-returned closure)
    : *u henv # *u h 1
    ? != # i henv 0 { ( nurl_free # s henv ) } {}

    ? == g_fail 0 { ( nurl_print `ALL PASS\n` ) ^ 0 } { ( nurl_print `FAILURES\n` ) ^ 1 }
}

// compress_rawdeflate.nu — raw-DEFLATE streaming codec in
// stdlib/ext/compress.nu (RFC 1951 bare blocks, persistent z_stream with
// Z_SYNC_FLUSH + context takeover). This is the engine RFC 7692 WebSocket
// permessage-deflate rides on, so it is exercised in isolation here.

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/compress.nu`

@ vec_eq_bytes ( Vec u ) a ( Vec u ) b → b {
    : i na ( vec_len [u] a )
    : i nb ( vec_len [u] b )
    ? != na nb { ^ F } {}
    : *u pa ( vec_data [u] a )
    : *u pb ( vec_data [u] b )
    : ~ i k 0
    ~ < k na {
        ? != # i . pa k # i . pb k { ^ F } {}
        = k + k 1
    }
    ^ T
}

@ make_input s sample i reps → ( Vec u ) {
    : ( Vec u ) buf ( vec_with_cap [u] 1024 )
    : ~ i k 0
    ~ < k reps {
        ( bytes_extend_str buf sample )
        = k + k 1
    }
    ^ buf
}

// permessage-deflate sender: compress, then strip the trailing
// `00 00 FF FF` the sync flush appends (RFC 7692 §7.2.1).
@ pmce_compress ZDeflate d ( Vec u ) input → ( Vec u ) {
    : !( Vec u ) CompressErr r ( raw_deflate_block d input )
    ^ ?? r {
        T comp → {
            : i cn ( vec_len [u] comp )
            ? >= cn 4 {
                : *u cp ( vec_data [u] comp )
                ? & & & == # i . cp - cn 4 0 == # i . cp - cn 3 0
                == # i . cp - cn 2 255 == # i . cp - cn 1 255 {
                    : b _t ( vec_set_len [u] comp - cn 4 )
                } {}
            } {}
            comp
        }
        F _ → ( vec_new [u] )
    }
}

// permessage-deflate receiver: re-append the `00 00 FF FF` tail, inflate.
@ pmce_decompress ZInflate d ( Vec u ) comp → ( Vec u ) {
    : ( Vec u ) framed ( vec_new [u] )
    ( vec_extend [u] framed comp )
    ( vec_push [u] framed # u 0 )
    ( vec_push [u] framed # u 0 )
    ( vec_push [u] framed # u 255 )
    ( vec_push [u] framed # u 255 )
    : !( Vec u ) CompressErr r ( raw_inflate_block d framed 0 )
    ( vec_free [u] framed )
    ^ ?? r {
        T plain → { plain }
        F _ → ( vec_new [u] )
    }
}

@ main → i {
    // ── §A round-trip with context takeover across 3 messages ───────
    : !ZDeflate CompressErr dn ( raw_deflate_new 15 6 )
    : !ZInflate CompressErr in ( raw_inflate_new 15 )
    ?? dn {
        T deflater → {
            ?? in {
                T inflater → {
                    : ( Vec u ) m1 ( make_input `the quick brown fox jumps over the lazy dog. ` 8 )
                    : ( Vec u ) m2 ( make_input `the quick brown fox jumps over the lazy dog. ` 8 )
                    : ( Vec u ) m3 ( make_input `NURL permessage-deflate over RFC 7692. ` 12 )

                    : ( Vec u ) c1 ( pmce_compress deflater m1 )
                    : ( Vec u ) p1 ( pmce_decompress inflater c1 )
                    // Second identical message must compress SMALLER because
                    // the sliding window survived (context takeover proof).
                    : ( Vec u ) c2 ( pmce_compress deflater m2 )
                    : ( Vec u ) p2 ( pmce_decompress inflater c2 )
                    : ( Vec u ) c3 ( pmce_compress deflater m3 )
                    : ( Vec u ) p3 ( pmce_decompress inflater c3 )

                    ( nurl_print `m1 round_trip=` )
                    ( nurl_print ? ( vec_eq_bytes m1 p1 ) `T` `F` )
                    ( nurl_print ` compressed_smaller=` )
                    ( nurl_print ? < ( vec_len [u] c1 ) ( vec_len [u] m1 ) `T` `F` )
                    ( nurl_print `\n` )
                    ( nurl_print `m2 round_trip=` )
                    ( nurl_print ? ( vec_eq_bytes m2 p2 ) `T` `F` )
                    ( nurl_print ` takeover_shrinks=` )
                    ( nurl_print ? < ( vec_len [u] c2 ) ( vec_len [u] c1 ) `T` `F` )
                    ( nurl_print `\n` )
                    ( nurl_print `m3 round_trip=` )
                    ( nurl_print ? ( vec_eq_bytes m3 p3 ) `T` `F` )
                    ( nurl_print `\n` )

                    ( vec_free [u] m1 ) ( vec_free [u] m2 ) ( vec_free [u] m3 )
                    ( vec_free [u] c1 ) ( vec_free [u] c2 ) ( vec_free [u] c3 )
                    ( vec_free [u] p1 ) ( vec_free [u] p2 ) ( vec_free [u] p3 )
                    ( raw_inflate_free inflater )
                }
                F _ → { ( nurl_print `inflate_new failed\n` ) ( raw_inflate_free in ) }
            }
            ( raw_deflate_free deflater )
        }
        F _ → { ( nurl_print `deflate_new failed\n` ) ( raw_deflate_free dn ) }
    }

    // ── §B no-context-takeover: reset between messages ──────────────
    // Two identical messages each compressed from a fresh window must
    // produce IDENTICAL output (deterministic, no carried state).
    : !ZDeflate CompressErr dn2 ( raw_deflate_new 15 6 )
    ?? dn2 {
        T deflater → {
            : ( Vec u ) a ( make_input `reset me between every websocket message. ` 6 )
            : ( Vec u ) b ( make_input `reset me between every websocket message. ` 6 )
            : ( Vec u ) ca ( pmce_compress deflater a )
            ( raw_deflate_reset deflater )
            : ( Vec u ) cb ( pmce_compress deflater b )
            ( nurl_print `no_takeover_identical=` )
            ( nurl_print ? ( vec_eq_bytes ca cb ) `T` `F` )
            ( nurl_print `\n` )
            ( vec_free [u] a ) ( vec_free [u] b )
            ( vec_free [u] ca ) ( vec_free [u] cb )
            ( raw_deflate_free deflater )
        }
        F _ → ( nurl_print `dn2 failed\n` )
    }

    // ── §C empty message round-trips ────────────────────────────────
    : !ZDeflate CompressErr dn3 ( raw_deflate_new 15 6 )
    : !ZInflate CompressErr in3 ( raw_inflate_new 15 )
    ?? dn3 {
        T deflater → {
            ?? in3 {
                T inflater → {
                    : ( Vec u ) empty ( vec_new [u] )
                    : ( Vec u ) ce ( pmce_compress deflater empty )
                    : ( Vec u ) pe ( pmce_decompress inflater ce )
                    ( nurl_print `empty round_trip=` )
                    ( nurl_print ? == ( vec_len [u] pe ) 0 `T` `F` )
                    ( nurl_print `\n` )
                    ( vec_free [u] empty ) ( vec_free [u] ce ) ( vec_free [u] pe )
                    ( raw_inflate_free inflater )
                }
                F _ → { ( nurl_print `in3 failed\n` ) ( raw_inflate_free in3 ) }
            }
            ( raw_deflate_free deflater )
        }
        F _ → { ( nurl_print `dn3 failed\n` ) ( raw_deflate_free dn3 ) }
    }

    // ── §D corrupt compressed input is rejected ─────────────────────
    : !ZInflate CompressErr in4 ( raw_inflate_new 15 )
    ?? in4 {
        T inflater → {
            : ( Vec u ) garbage ( vec_with_cap [u] 8 )
            ( vec_push [u] garbage # u 255 )
            ( vec_push [u] garbage # u 255 )
            ( vec_push [u] garbage # u 255 )
            ( vec_push [u] garbage # u 255 )
            : !( Vec u ) CompressErr r ( raw_inflate_block inflater garbage 0 )
            ?? r {
                T v → { ( nurl_print `garbage: unexpected ok\n` ) ( vec_free [u] v ) }
                F e → {
                    ( nurl_print `garbage rejected=` )
                    ( nurl_print ( compress_err_name e ) ) ( nurl_print `\n` )
                }
            }
            ( vec_free [u] garbage )
            ( raw_inflate_free inflater )
        }
        F _ → ( nurl_print `in4 failed\n` )
    }
    ^ 0
}

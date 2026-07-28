// tests/weightscheck.nu — the lw_* shim against the real checkpoint.
//
// Opens the cached facebook/map-anything-apache model.safetensors and
// checks the facts the port is built on: tensor count, the encoder /
// info_sharing layer counts read off the file, a handful of shapes, and
// that lw_read agrees with lw_f32_ptr on real bytes.
//
//   nurlc tests/weightscheck.nu -o /tmp/wc && /tmp/wc [path]

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/floatbits.nu`
$ `src/weights.nu`

: i WC_DIM 1536

@ __wc_default → s {
    ^ `/home/wau/.nurl/models/models/facebook_map-anything-apache/snapshots/main/model.safetensors`
}

: ~ i __wc_fails 0

@ __wc_check b ok s what → v {
    : String m ( string_from ? ok `ok   ` `FAIL ` )
    ( string_push_str m what )
    ( puts ( string_data m ) )
    ( string_free m )
    ? ok {} { = __wc_fails + __wc_fails 1 }
}

@ main → i {
    : ~ s path ( __wc_default )
    ? > ( nurl_argc ) 1 { = path ( nurl_argv 1 ) } {}
    : !*Lw String r ( lw_open path )
    : ~ * Lw w # *Lw 0
    ?? r {
        F e → {
            : String m ( string_from `cannot open checkpoint: ` )
            ( string_push_str m ( string_data e ) )
            ( puts ( string_data m ) )
            ( string_free m )
            ( string_free e )
            ^ 1
        }
        T got → { = w got }
    }

    ( __wc_check == ( lw_n_tensors w ) 736 `736 tensors` )

    // Layer counts, read off the file.
    : i enc_layers ( lw_count_indexed w `encoder.model.blocks.` `.attn.qkv.weight` )
    ( __wc_check == enc_layers 24 `encoder has 24 blocks` )
    : i agg_layers ( lw_count_indexed w `info_sharing.self_attention_blocks.` `.attn.qkv.weight` )
    ( __wc_check == agg_layers 16 `info_sharing has 16 blocks` )

    // Shapes the config promises.
    ( __wc_check ( lw_require w `encoder.model.cls_token` 1 1 WC_DIM -1 ) `cls_token [1,1,1536]` )
    ( __wc_check ( lw_require w `encoder.model.pos_embed` 1 1370 WC_DIM -1 ) `pos_embed [1,1370,1536]` )
    ( __wc_check ( lw_require w `scale_token` WC_DIM -1 -1 -1 ) `scale_token [1536]` )
    ( __wc_check ( lw_require w `pose_head.fc_rot.weight` 4 784 -1 -1 ) `pose_head.fc_rot [4,784]` )
    ( __wc_check ( lw_require w `pose_head.fc_t.weight` 3 784 -1 -1 ) `pose_head.fc_t [3,784]` )
    ( __wc_check ( lw_require w `encoder.model.blocks.0.mlp.w12.weight` 8192 WC_DIM -1 -1 ) `encoder swiglu w12 [8192,1536]` )
    ( __wc_check ( lw_require w `dense_head.1.conv2.2.weight` 6 128 1 1 ) `dense head emits 6 channels` )
    ( __wc_check ( lw_ok w ) `no accumulated shape errors` )

    // lw_read (through the f32 dequant path) must agree with the raw
    // mapping bytes lw_f32_ptr exposes.
    : i n ( lw_nelems w `scale_token` )
    ( __wc_check == n WC_DIM `scale_token has 1536 elements` )
    : *f host # *f ( nurl_alloc * n 8 )
    ( __wc_check ( lw_read w `scale_token` host n ) `lw_read scale_token` )
    : *u raw ( lw_f32_ptr w `scale_token` n )
    ( __wc_check != # i raw 0 `lw_f32_ptr sees contiguous f32` )
    : ~ b same T
    : ~ i k 0
    ~ < k n {
        : i o * k 4
        : i bits | # i . raw o | << # i . raw + o 1 8 | << # i . raw + o 2 16 << # i . raw + o 3 24
        : f want # f ( bits_to_f32 bits )
        ? == want . host k {} { = same F }
        = k + k 1
    }
    ( __wc_check same `lw_read == mapping bytes for all 1536 elements` )
    ( nurl_free # s host )

    ( lw_close w )

    // A missing tensor records exactly one loud error — on a fresh handle,
    // so the message checked is the FIRST one (lw_error keeps only that).
    : !*Lw String r2 ( lw_open path )
    ?? r2 {
        F e → { ( string_free e ) ( __wc_check F `reopen for negative test` ) }
        T w2 → {
            : b _m ( lw_require w2 `no.such.tensor` -1 -1 -1 -1 )
            ( __wc_check ! ( lw_ok w2 ) `missing tensor recorded` )
            ( __wc_check ( nurl_str_eq ( lw_error w2 ) `map-anything: checkpoint has no tensor 'no.such.tensor'` ) `error names the tensor` )
            ( lw_close w2 )
        }
    }
    ? == __wc_fails 0 { ( puts `weightscheck: all ok` ) ^ 0 } {}
    ( puts `weightscheck: FAILURES` )
    ^ 1
}

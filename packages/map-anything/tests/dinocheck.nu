// tests/dinocheck.nu — the ported encoder against the reference.
//
// tests/dino_oracle.py wrote input.bin ([3,H,W] f32 planar, already in
// "normalised" range) and ref_tok.bin ([1+gh·gw, 1536] f32). This runs
// dn_forward over the same input and writes nurl_tok.bin in the same
// layout; tests/cmp_bin.py reports the max abs/rel difference.
//
//   dinocheck <model.safetensors> <dir> <H> <W>

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/floatbits.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`
$ `deps/gpukit/src/devops.nu`
$ `src/weights.nu`
$ `src/devblock.nu`
$ `src/load.nu`
$ `src/interp.nu`
$ `src/patchembed.nu`
$ `src/dino.nu`

@ __dc_die s msg → i {
    ( puts msg )
    ^ 1
}

@ main → i {
    ? < ( nurl_argc ) 5 { ^ ( __dc_die `usage: dinocheck <model> <dir> <H> <W>` ) } {}
    : s model ( nurl_argv 1 )
    : s dir ( nurl_argv 2 )
    : i h ( nurl_str_to_int ( nurl_argv 3 ) )
    : i w ( nurl_str_to_int ( nurl_argv 4 ) )
    : i gh / h 14
    : i gw / w 14

    // input.bin → host f64 planes
    : String ip ( string_from dir )
    ( string_push_str ip `/input.bin` )
    : ~ ( Vec u ) raw ( vec_new [u] )
    ?? ( read_file_bytes ( string_data ip ) ) {
        T v → { ( vec_free [u] raw ) = raw v }
        F → { ^ ( __dc_die `cannot read input.bin` ) }
    }
    ( string_free ip )
    : i nin * 3 * h w
    ? != ( vec_len [u] raw ) * nin 4 { ^ ( __dc_die `input.bin is the wrong size` ) } {}
    : *f img # *f ( nurl_zalloc * 8 nin )
    : *u rp ( vec_data [u] raw )
    : ~ i j 0
    ~ < j nin {
        : i o * j 4
        : i bits | # i . rp o | << # i . rp + o 1 8 | << # i . rp + o 2 16 << # i . rp + o 3 24
        = . img j # f ( bits_to_f32 bits )
        = j + j 1
    }
    ( vec_free [u] raw )

    // model + device
    : ~ * Lw lw # *Lw 0
    ?? ( lw_open model ) {
        F e → {
            ( puts ( string_data e ) )
            ( string_free e )
            ^ 1
        }
        T got → { = lw got }
    }
    : *GpuKit kit ( gk_open_best )
    ? ( gk_ok kit ) {} { ^ ( __dc_die `no compute device` ) }
    : Dino d ( dn_load lw kit )
    ? ( lw_ok lw ) {} { ^ ( __dc_die ( lw_error lw ) ) }

    : i n ( dn_tokens gh gw )
    : MaWs ws ( ma_ws_new kit n DN_DIM DN_HEADS DN_SWH )
    : GkBuf tok ( gk_dbuf_new kit * n DN_DIM GK_F32 )
    ? ( dn_forward kit d ws img h w gh gw tok ) {} { ^ ( __dc_die `dn_forward failed` ) }

    // download and write nurl_tok.bin as f32
    : ( Vec f ) host ( vec_with_cap [f] * n DN_DIM )
    : b _hl ( vec_set_len [f] host * n DN_DIM )
    ? ( gk_dbuf_download kit tok host ) {} { ^ ( __dc_die `download failed` ) }
    : ( Vec u ) out ( vec_with_cap [u] * * n DN_DIM 4 )
    : b _ol ( vec_set_len [u] out * * n DN_DIM 4 )
    : *u op ( vec_data [u] out )
    : *f hp ( vec_data [f] host )
    = j 0
    ~ < j * n DN_DIM {
        : i bits # i ( f32_to_bits # f32 . hp j )
        : i o * j 4
        = . op o # u & bits 255
        = . op + o 1 # u & >> bits 8 255
        = . op + o 2 # u & >> bits 16 255
        = . op + o 3 # u & >> bits 24 255
        = j + j 1
    }
    : String opth ( string_from dir )
    ( string_push_str opth `/nurl_tok.bin` )
    ?? ( write_file_bytes ( string_data opth ) out ) {
        T → { ( puts `wrote nurl_tok.bin` ) }
        F → { ^ ( __dc_die `cannot write nurl_tok.bin` ) }
    }
    ( string_free opth )
    ( vec_free [u] out )
    ( vec_free [f] host )
    ( gk_dbuf_free tok )
    ( ma_ws_free ws )
    ( dn_free d )
    ( lw_close lw )
    ( nurl_free # s img )
    ( gk_close kit )
    ^ 0
}

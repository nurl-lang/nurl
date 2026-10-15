// tests/dptcheck.nu — the ported DPT head against the reference.
// Reads hooks.bin (4 sequence-layout tapped features for one view),
// runs dp_forward, writes nurl_{rays,depth,conf,mask}.bin.
//
//   dptcheck <model.safetensors> <dir> <gh> <gw>

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
$ `src/dpthead.nu`

@ __dt_die s msg → i {
    ( puts msg )
    ^ 1
}

unsafe @ __dt_up GpuKit kit ( Slice u ) raw i off i n → GkBuf {
    : ( Vec f ) host ( vec_zeroed [f] n )
    : ( Slice f ) hp ( slice_from_vec [f] host )
    : ~ i j 0
    ~ < j n {
        : i o * + off j 4
        : i bits | # i ( slice_at [u] raw o ) | << # i ( slice_at [u] raw + o 1 ) 8 | << # i ( slice_at [u] raw + o 2 ) 16 << # i ( slice_at [u] raw + o 3 ) 24
        ( slice_put [f] hp j # f ( bits_to_f32 bits ) )
        = j + j 1
    }
    : GkBuf b ( gk_dbuf_new kit n GK_F32 )
    : b _u ( gk_dbuf_upload kit b host )
    ^ b
}

unsafe @ __dt_dump GpuKit kit s dir s name GkBuf b i n → b {
    : ( Vec f ) host ( vec_zeroed [f] n )
    ? ( gk_dbuf_download kit b host ) {} { ^ F }
    : ( Vec u ) out ( vec_zeroed [u] * n 4 )
    : ( Slice u ) op ( slice_from_vec [u] out )
    : ( Slice f ) hp ( slice_from_vec [f] host )
    : ~ i j 0
    ~ < j n {
        : i bits # i ( f32_to_bits # f32 ( slice_at [f] hp j ) )
        : i o * j 4
        ( slice_put [u] op o # u & bits 255 )
        ( slice_put [u] op + o 1 # u & >> bits 8 255 )
        ( slice_put [u] op + o 2 # u & >> bits 16 255 )
        ( slice_put [u] op + o 3 # u & >> bits 24 255 )
        = j + j 1
    }
    : String p ( string_from dir )
    ( string_push_str p name )
    : ~ b ok F
    ?? ( write_file_bytes ( string_data p ) out ) {
        T → { = ok T }
        F → {}
    }
    ^ ok
}

unsafe @ main → i {
    ? < ( nurl_argc ) 5 { ^ ( __dt_die `usage: dptcheck <model> <dir> <gh> <gw>` ) } {}
    : s model ( nurl_argv 1 )
    : s dir ( nurl_argv 2 )
    : i gh ( nurl_str_to_int ( nurl_argv 3 ) )
    : i gw ( nurl_str_to_int ( nurl_argv 4 ) )
    : i np * gh gw
    : i h * gh 14
    : i w * gw 14

    : String hp ( string_from dir )
    ( string_push_str hp `/hooks.bin` )
    : ~ ( Vec u ) raw ( vec_new [u] )
    ?? ( read_file_bytes ( string_data hp ) ) {
        T v → { = raw v }
        F → { ^ ( __dt_die `cannot read hooks.bin` ) }
    }
    ? == ( vec_len [u] raw ) * * 4 * np 1536 4 {} { ^ ( __dt_die `hooks.bin wrong size` ) }

    : Lw lw ?? ( lw_open model ) {
        F e → {
            ( puts ( string_data e ) )
            ^ 1
        }
        T got → got
    }
    : GpuKit kit ( gk_open_best )
    ? ( gk_ok kit ) {} { ^ ( __dt_die `no compute device` ) }
    : Dpt d ( dp_load lw kit )
    ? ( lw_ok lw ) {} { ^ ( __dt_die ( string_data ( lw_error lw ) ) ) }

    : ( Slice u ) rp ( slice_from_vec [u] raw )
    : i per * np 1536
    : GkBuf h0 ( __dt_up kit rp 0 per )
    : GkBuf h1 ( __dt_up kit rp per per )
    : GkBuf h2 ( __dt_up kit rp * 2 per per )
    : GkBuf h3 ( __dt_up kit rp * 3 per per )

    : i hw * h w
    : GkBuf rays ( gk_dbuf_new kit * 3 hw GK_F32 )
    : GkBuf depth ( gk_dbuf_new kit hw GK_F32 )
    : GkBuf conf ( gk_dbuf_new kit hw GK_F32 )
    : GkBuf mask ( gk_dbuf_new kit hw GK_F32 )
    ? ( dp_forward kit d h0 h1 h2 h3 0 gh gw h w rays depth conf mask ) {}
    { ^ ( __dt_die `dp_forward failed` ) }

    ? ( __dt_dump kit dir `/nurl_rays.bin` rays * 3 hw ) {} { ^ ( __dt_die `dump rays` ) }
    ? ( __dt_dump kit dir `/nurl_depth.bin` depth hw ) {} { ^ ( __dt_die `dump depth` ) }
    ? ( __dt_dump kit dir `/nurl_conf.bin` conf hw ) {} { ^ ( __dt_die `dump conf` ) }
    ? ( __dt_dump kit dir `/nurl_mask.bin` mask hw ) {} { ^ ( __dt_die `dump mask` ) }
    ( puts `wrote nurl_rays/depth/conf/mask.bin` )
    ^ 0
}

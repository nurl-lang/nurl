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

@ __dt_up * GpuKit kit * u raw i off i n → GkBuf {
    : ( Vec f ) host ( vec_with_cap [f] n )
    : b _l ( vec_set_len [f] host n )
    : *f hp ( vec_data [f] host )
    : ~ i j 0
    ~ < j n {
        : i o * + off j 4
        : i bits | # i . raw o | << # i . raw + o 1 8 | << # i . raw + o 2 16 << # i . raw + o 3 24
        = . hp j # f ( bits_to_f32 bits )
        = j + j 1
    }
    : GkBuf b ( gk_dbuf_new kit n GK_F32 )
    : b _u ( gk_dbuf_upload kit b host )
    ( vec_free [f] host )
    ^ b
}

@ __dt_dump * GpuKit kit s dir s name GkBuf b i n → b {
    : ( Vec f ) host ( vec_with_cap [f] n )
    : b _hl ( vec_set_len [f] host n )
    ? ( gk_dbuf_download kit b host ) {} { ^ F }
    : ( Vec u ) out ( vec_with_cap [u] * n 4 )
    : b _ol ( vec_set_len [u] out * n 4 )
    : *u op ( vec_data [u] out )
    : *f hp ( vec_data [f] host )
    : ~ i j 0
    ~ < j n {
        : i bits # i ( f32_to_bits # f32 . hp j )
        : i o * j 4
        = . op o # u & bits 255
        = . op + o 1 # u & >> bits 8 255
        = . op + o 2 # u & >> bits 16 255
        = . op + o 3 # u & >> bits 24 255
        = j + j 1
    }
    : String p ( string_from dir )
    ( string_push_str p name )
    : ~ b ok F
    ?? ( write_file_bytes ( string_data p ) out ) {
        T → { = ok T }
        F → {}
    }
    ( string_free p )
    ( vec_free [u] out )
    ( vec_free [f] host )
    ^ ok
}

@ main → i {
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
        T v → { ( vec_free [u] raw ) = raw v }
        F → { ^ ( __dt_die `cannot read hooks.bin` ) }
    }
    ( string_free hp )
    ? == ( vec_len [u] raw ) * * 4 * np 1536 4 {} { ^ ( __dt_die `hooks.bin wrong size` ) }

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
    ? ( gk_ok kit ) {} { ^ ( __dt_die `no compute device` ) }
    : Dpt d ( dp_load lw kit )
    ? ( lw_ok lw ) {} { ^ ( __dt_die ( lw_error lw ) ) }

    : *u rp ( vec_data [u] raw )
    : i per * np 1536
    : GkBuf h0 ( __dt_up kit rp 0 per )
    : GkBuf h1 ( __dt_up kit rp per per )
    : GkBuf h2 ( __dt_up kit rp * 2 per per )
    : GkBuf h3 ( __dt_up kit rp * 3 per per )
    ( vec_free [u] raw )

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

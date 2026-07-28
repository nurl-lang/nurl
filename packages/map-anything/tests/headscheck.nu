// tests/headscheck.nu — pose + scale heads against the reference.
// Reads pfeat.bin / stok.bin, runs ph_forward + sh_forward, writes
// nurl_pose.bin (7 f32) and nurl_scale.bin (1 f32).
//
//   headscheck <model.safetensors> <dir> <gh> <gw>

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
$ `src/heads.nu`

@ __hc_die s msg → i {
    ( puts msg )
    ^ 1
}

@ __hc_read_up * GpuKit kit s dir s name i n → GkBuf {
    : String p ( string_from dir )
    ( string_push_str p name )
    : ~ GkBuf out @ GkBuf { 0 0 GK_F32 }
    ?? ( read_file_bytes ( string_data p ) ) {
        F → {}
        T raw → {
            ? == ( vec_len [u] raw ) * n 4 {
                : ( Vec f ) host ( vec_with_cap [f] n )
                : b _l ( vec_set_len [f] host n )
                : *u rp ( vec_data [u] raw )
                : *f hp ( vec_data [f] host )
                : ~ i j 0
                ~ < j n {
                    : i o * j 4
                    : i bits | # i . rp o | << # i . rp + o 1 8 | << # i . rp + o 2 16 << # i . rp + o 3 24
                    = . hp j # f ( bits_to_f32 bits )
                    = j + j 1
                }
                : GkBuf b ( gk_dbuf_new kit n GK_F32 )
                : b _u ( gk_dbuf_upload kit b host )
                ( vec_free [f] host )
                = out b
            } {}
            ( vec_free [u] raw )
        }
    }
    ( string_free p )
    ^ out
}

@ __hc_write s dir s name * f vals i n → b {
    : ( Vec u ) out ( vec_with_cap [u] * n 4 )
    : b _ol ( vec_set_len [u] out * n 4 )
    : *u op ( vec_data [u] out )
    : ~ i j 0
    ~ < j n {
        : i bits # i ( f32_to_bits # f32 . vals j )
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
    ^ ok
}

@ main → i {
    ? < ( nurl_argc ) 5 { ^ ( __hc_die `usage: headscheck <model> <dir> <gh> <gw>` ) } {}
    : s model ( nurl_argv 1 )
    : s dir ( nurl_argv 2 )
    : i gh ( nurl_str_to_int ( nurl_argv 3 ) )
    : i gw ( nurl_str_to_int ( nurl_argv 4 ) )
    : i np * gh gw

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
    ? ( gk_ok kit ) {} { ^ ( __hc_die `no compute device` ) }
    : PoseH ph ( ph_load lw kit )
    : ScaleH sh ( sh_load lw kit )
    ? ( lw_ok lw ) {} { ^ ( __hc_die ( lw_error lw ) ) }

    : GkBuf feat ( __hc_read_up kit dir `/pfeat.bin` * np 1536 )
    : GkBuf stok ( __hc_read_up kit dir `/stok.bin` 1536 )
    ? & ( gk_buf_ok feat ) ( gk_buf_ok stok ) {} { ^ ( __hc_die `cannot read inputs` ) }

    : *f pose # *f ( nurl_zalloc 56 )
    ? ( ph_forward kit ph feat 0 np pose ) {} { ^ ( __hc_die `ph_forward failed` ) }
    : f scale ( sh_forward kit sh stok 0 )
    ? > scale 0.0 {} { ^ ( __hc_die `sh_forward failed` ) }

    ? ( __hc_write dir `/nurl_pose.bin` pose 7 ) {} { ^ ( __hc_die `write pose` ) }
    : *f sv # *f ( nurl_zalloc 8 )
    = . sv 0 scale
    ? ( __hc_write dir `/nurl_scale.bin` sv 1 ) {} { ^ ( __hc_die `write scale` ) }
    ( puts `wrote nurl_pose/scale.bin` )
    ^ 0
}

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

unsafe @ __hc_read_up GpuKit kit s dir s name i n → GkBuf {
    : String p ( string_from dir )
    ( string_push_str p name )
    : ~ GkBuf out ( gk_buf_none GK_F32 )
    ?? ( read_file_bytes ( string_data p ) ) {
        F → {}
        T raw → {
            ? == ( vec_len [u] raw ) * n 4 {
                : ( Vec f ) host ( vec_zeroed [f] n )
                : ( Slice u ) rp ( slice_from_vec [u] raw )
                : ( Slice f ) hp ( slice_from_vec [f] host )
                : ~ i j 0
                ~ < j n {
                    : i o * j 4
                    : i bits | # i ( slice_at [u] rp o ) | << # i ( slice_at [u] rp + o 1 ) 8 | << # i ( slice_at [u] rp + o 2 ) 16 << # i ( slice_at [u] rp + o 3 ) 24
                    ( slice_put [f] hp j # f ( bits_to_f32 bits ) )
                    = j + j 1
                }
                : GkBuf b ( gk_dbuf_new kit n GK_F32 )
                : b _u ( gk_dbuf_upload kit b host )
                = out b
            } {}
        }
    }
    ^ out
}

unsafe @ __hc_write s dir s name ( Slice f ) vals i n → b {
    : ( Vec u ) out ( vec_zeroed [u] * n 4 )
    : ( Slice u ) op ( slice_from_vec [u] out )
    : ~ i j 0
    ~ < j n {
        : i bits # i ( f32_to_bits # f32 ( slice_at [f] vals j ) )
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
    ? < ( nurl_argc ) 5 { ^ ( __hc_die `usage: headscheck <model> <dir> <gh> <gw>` ) } {}
    : s model ( nurl_argv 1 )
    : s dir ( nurl_argv 2 )
    : i gh ( nurl_str_to_int ( nurl_argv 3 ) )
    : i gw ( nurl_str_to_int ( nurl_argv 4 ) )
    : i np * gh gw

    : Lw lw ?? ( lw_open model ) {
        F e → {
            ( puts ( string_data e ) )
            ^ 1
        }
        T got → got
    }
    : GpuKit kit ( gk_open_best )
    ? ( gk_ok kit ) {} { ^ ( __hc_die `no compute device` ) }
    : PoseH ph ( ph_load lw kit )
    : ScaleH sh ( sh_load lw kit )
    ? ( lw_ok lw ) {} { ^ ( __hc_die ( string_data ( lw_error lw ) ) ) }

    : GkBuf feat ( __hc_read_up kit dir `/pfeat.bin` * np 1536 )
    : GkBuf stok ( __hc_read_up kit dir `/stok.bin` 1536 )
    ? & ( gk_buf_ok feat ) ( gk_buf_ok stok ) {} { ^ ( __hc_die `cannot read inputs` ) }

    : ( Vec f ) pose__v ( vec_zeroed [f] 7 )
    : ( Slice f ) pose ( slice_from_vec [f] pose__v )
    ? ( ph_forward kit ph feat 0 np pose ) {} { ^ ( __hc_die `ph_forward failed` ) }
    : f scale ( sh_forward kit sh stok 0 )
    ? > scale 0.0 {} { ^ ( __hc_die `sh_forward failed` ) }

    ? ( __hc_write dir `/nurl_pose.bin` pose 7 ) {} { ^ ( __hc_die `write pose` ) }
    : ( Vec f ) sv__v ( vec_zeroed [f] 1 )
    : ( Slice f ) sv ( slice_from_vec [f] sv__v )
    ( slice_put [f] sv 0 scale )
    ? ( __hc_write dir `/nurl_scale.bin` sv 1 ) {} { ^ ( __hc_die `write scale` ) }
    ( puts `wrote nurl_pose/scale.bin` )
    ^ 0
}

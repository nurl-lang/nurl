// tests/infosharecheck.nu — the ported info_sharing against the
// reference. Reads the synthetic inputs infoshare_oracle.py wrote,
// assembles the sequence, runs is_finish_input + is_forward, and writes
// nurl_tap7 / nurl_tap11 / nurl_fin.bin for cmp_bin.py. The taps are
// compared over the first V*(np+1) rows (the oracle does not carry the
// scale token through its intermediate outputs), the final over all.
//
//   infosharecheck <model.safetensors> <dir> <V> <gh> <gw>

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
$ `src/infoshare.nu`

@ __ic_die s msg → i {
    ( puts msg )
    ^ 1
}

unsafe @ __ic_read s dir s name i want → ( Vec f ) {
    : String p ( string_from dir )
    ( string_push_str p name )
    : ( Vec f ) out ( vec_with_cap [f] ? > want 0 want 1 )
    ?? ( read_file_bytes ( string_data p ) ) {
        F → {}
        T raw → {
            ? == ( vec_len [u] raw ) * want 4 {
                : b _l ( vec_set_len [f] out want )
                : ( Slice u ) rp ( slice_from_vec [u] raw )
                : ( Slice f ) op ( slice_from_vec [f] out )
                : ~ i j 0
                ~ < j want {
                    : i o * j 4
                    : i bits | # i ( slice_at [u] rp o ) | << # i ( slice_at [u] rp + o 1 ) 8 | << # i ( slice_at [u] rp + o 2 ) 16 << # i ( slice_at [u] rp + o 3 ) 24
                    ( slice_put [f] op j # f ( bits_to_f32 bits ) )
                    = j + j 1
                }
            } {}
        }
    }
    ^ out
}

unsafe @ __ic_dump GpuKit kit s dir s name GkBuf b i n → b {
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
    ? < ( nurl_argc ) 6 { ^ ( __ic_die `usage: infosharecheck <model> <dir> <V> <gh> <gw>` ) } {}
    : s model ( nurl_argv 1 )
    : s dir ( nurl_argv 2 )
    : i nv ( nurl_str_to_int ( nurl_argv 3 ) )
    : i gh ( nurl_str_to_int ( nurl_argv 4 ) )
    : i gw ( nurl_str_to_int ( nurl_argv 5 ) )
    : i np * gh gw
    : i tpv + np 1
    : i n ( is_tokens nv np )

    : ( Vec f ) feats ( __ic_read dir `/feats.bin` * nv * np IS_DIM )
    : ( Vec f ) regs ( __ic_read dir `/regs.bin` * nv IS_DIM )
    ? & > ( vec_len [f] feats ) 0 > ( vec_len [f] regs ) 0 {} {
        ^ ( __ic_die `cannot read feats.bin / regs.bin` )
    }

    : Lw lw ?? ( lw_open model ) {
        F e → {
            ( puts ( string_data e ) )
            ^ 1
        }
        T got → got
    }
    : GpuKit kit ( gk_open_best )
    ? ( gk_ok kit ) {} { ^ ( __ic_die `no compute device` ) }
    : InfoShare ish ( is_load lw kit )
    ? ( lw_ok lw ) {} { ^ ( __ic_die ( string_data ( lw_error lw ) ) ) }

    // Assemble the UN-normed sequence on the host: per view patches
    // then cls, scale row left zero for is_finish_input to fill.
    : ( Vec f ) hx ( vec_zeroed [f] * n IS_DIM )
    : ( Slice f ) xp ( slice_from_vec [f] hx )
    : ( Slice f ) fp ( slice_from_vec [f] feats )
    : ( Slice f ) rp ( slice_from_vec [f] regs )
    : ~ i v 0
    ~ < v nv {
        : i vbase * * v tpv IS_DIM
        : ~ i j 0
        ~ < j * np IS_DIM {
            ( slice_put [f] xp + vbase j ( slice_at [f] fp + * * v np IS_DIM j ) )
            = j + j 1
        }
        = j 0
        ~ < j IS_DIM {
            ( slice_put [f] xp + + vbase * np IS_DIM j ( slice_at [f] rp + * v IS_DIM j ) )
            = j + j 1
        }
        = v + v 1
    }
    : ~ i z * * nv tpv IS_DIM
    ~ < z * n IS_DIM { ( slice_put [f] xp z 0.0 ) = z + z 1 }

    : GkBuf x ( gk_dbuf_new kit * n IS_DIM GK_F32 )
    ? ( gk_dbuf_upload kit x hx ) {} { ^ ( __ic_die `upload failed` ) }

    ? ( is_finish_input kit ish x nv np ) {} { ^ ( __ic_die `is_finish_input failed` ) }
    : MaWs ws ( ma_ws_new kit n IS_DIM IS_HEADS IS_SWH )
    : GkBuf i7 ( gk_dbuf_new kit * n IS_DIM GK_F32 )
    : GkBuf i11 ( gk_dbuf_new kit * n IS_DIM GK_F32 )
    : GkBuf fin ( gk_dbuf_new kit * n IS_DIM GK_F32 )
    ? ( is_forward kit ish ws x nv np i7 i11 fin ) {} { ^ ( __ic_die `is_forward failed` ) }

    // The oracle's tap files carry only the view rows.
    : i ntap * * nv tpv IS_DIM
    ? ( __ic_dump kit dir `/nurl_tap7.bin` ( ma_view i7 0 ntap ) ntap ) {} { ^ ( __ic_die `dump tap7` ) }
    ? ( __ic_dump kit dir `/nurl_tap11.bin` ( ma_view i11 0 ntap ) ntap ) {} { ^ ( __ic_die `dump tap11` ) }
    ? ( __ic_dump kit dir `/nurl_fin.bin` fin * n IS_DIM ) {} { ^ ( __ic_die `dump fin` ) }
    ( puts `wrote nurl_tap7/tap11/fin.bin` )
    ^ 0
}

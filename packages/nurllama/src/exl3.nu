// packages/nurllama/src/exl3.nu — EXL3 weights (exllamav3's trellis
// quantisation) on the device: the codebook tables, and a linear's tensor
// group loaded from a safetensors file into an LkW the matvec runs (the
// kernels and the format: kernels.nu, "EXL3").
//
//   ( exl3_luts kit )                      → Exl3Luts   the three tables
//   ( exl3_upload kit st prefix luts aux ) → !LkW String
//
// A linear `prefix` is stored as
//   prefix.trellis  I16 [k/16, n/16, 16·K]   the tiles' bit rings
//   prefix.suh      F16 [k]                  input signs / scales
//   prefix.svh      F16 [n]                  output signs / scales
//   prefix.mcg | prefix.mul1                 the codebook's marker (none:
//                                            3INST); its value is unused
// K (bits per weight, or a half-integer) follows from the ring length.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`
$ `deps/safetensor/src/safetensor.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`
$ `kernels.nu`

// One value of codebook `cb` (0 3INST, 1 MCG, 2 MUL1) for 16-bit state
// `st`, as an f32 holding the fp16 the CUDA kernels compute. Both forms are
// exact before their one fp16 rounding (the two halves of 3INST / MCG have
// exponents 12..15, so their sum fits a float; MUL1's (1024 + bytesum) ·
// k_inv + k_bias is 23 significant bits), so the rounding here is theirs.
@ exl3_cb_value i cb i st → f {
    : i m32 4294967295
    ? == cb 2 {
        : i x & * st 2212286765 m32  // 0x83DCD12D
        : i bsum + + & x 255 & >> x 8 255 + & >> x 16 255 & >> x 24 255
        : f kinv ( f16_to_f 7918 )  // 0x1EEE
        : f kbias ( f16_to_f 51505 )  // 0xC931
        : f v + * # f + 1024 bsum kinv kbias
        ^ ( f16_to_f ( f_to_f16 v ) )
    } {}
    : ~ i x 0
    ? == cb 1 { = x & * st 3417055213 m32 } { = x & + * st 89226354 64248484 m32 }  // 0xCBAC1FED
    = x ^^ & x 2415890431 996162400  // (x & 0x8FFF8FFF) ^ 0x3B603B60
    : f v + ( f16_to_f & x 65535 ) ( f16_to_f >> x 16 )
    ^ ( f16_to_f ( f_to_f16 v ) )
}

// A codebook's 65536 values as f32 little-endian bytes.
@ exl3_lut_bytes i cb → ( Vec u ) {
    : ( Vec u ) out ( vec_with_cap [u] * 65536 4 )
    : ~ i st 0
    ~ < st 65536 {
        ( bytes_push_f32_le out # f32 ( exl3_cb_value cb st ) )
        = st + st 1
    }
    ^ out
}

: Exl3Luts {
    GkBuf cb0
    GkBuf cb1
    GkBuf cb2
}

// The three codebook tables on the device (3 × 256 KB): every EXL3 weight
// reads its own codebook's.
@ exl3_luts GpuKit kit → Exl3Luts {
    : GkBuf a ( gk_dbuf_new kit 65536 GK_F32 )
    : GkBuf b ( gk_dbuf_new kit 65536 GK_F32 )
    : GkBuf c ( gk_dbuf_new kit 65536 GK_F32 )
    : b _a ( gk_dbuf_upload_bytes kit a ( slice_from_vec [u] ( exl3_lut_bytes 0 ) ) )
    : b _b ( gk_dbuf_upload_bytes kit b ( slice_from_vec [u] ( exl3_lut_bytes 1 ) ) )
    : b _c ( gk_dbuf_upload_bytes kit c ( slice_from_vec [u] ( exl3_lut_bytes 2 ) ) )
    ^ @ Exl3Luts { a b c }
}

@ __exl3_name s prefix s suffix → String {
    : String n ( string_from prefix )
    ( string_push_char n 46 )
    ( string_push_str n suffix )
    ^ n
}

@ __exl3_err s prefix s what → !LkW String {
    : String m ( string_from `EXL3 tensor ` )
    ( string_push_str m prefix )
    ( string_push_str m `: ` )
    ( string_push_str m what )
    ^ @ !LkW String { F m }
}

@ __exl3_append ( Vec u ) out ( Slice u ) b → v {
    : ~ i j 0
    ~ < j ( slice_len [u] b ) {
        ( vec_push [u] out ( slice_at [u] b j ) )
        = j + j 1
    }
}

// The tensor `name` of `st`, when it is there with dtype `dt`.
@ __exl3_tensor St st s name i dt → ?StTensor {
    : i ti ( st_find_tensor st name )
    ? < ti 0 { ^ @ ?StTensor { F } } {}
    : StTensor t ( vec_at [StTensor] ( st_tensors st ) ti )
    ? == . t dtype dt { ^ @ ?StTensor { T t } } {}
    ^ @ ?StTensor { F }
}

// The EXL3 linear `prefix` of `st` on the device; `aux` is the scratch its
// matvec rotates through (shared by every EXL3 weight; batch · (k + n)
// floats for the largest batch it will see).
@ exl3_upload GpuKit kit St st s prefix Exl3Luts luts GkBuf aux → !LkW String {
    : String tn ( __exl3_name prefix `trellis` )
    : String un ( __exl3_name prefix `suh` )
    : String vn ( __exl3_name prefix `svh` )
    : StTensor tt ?? ( __exl3_tensor st ( string_data tn ) ST_I16 ) { T t → t F → { ^ ( __exl3_err prefix `no I16 trellis` ) } }
    : StTensor ut ?? ( __exl3_tensor st ( string_data un ) ST_F16 ) { T t → t F → { ^ ( __exl3_err prefix `no F16 suh` ) } }
    : StTensor vt ?? ( __exl3_tensor st ( string_data vn ) ST_F16 ) { T t → t F → { ^ ( __exl3_err prefix `no F16 svh` ) } }
    ? == . tt nd 3 {} { ^ ( __exl3_err prefix `trellis is not [k/16, n/16, 16·K]` ) }
    : i k * . tt d0 16
    : i n * . tt d1 16
    // 16·K uint16 a tile: k2 = 2K (an integer for the half-integer rates)
    : i k2 / . tt d2 8
    ? | | | | != % . tt d2 8 0 < k2 2 > k2 16 != . ut nelems k != . vt nelems n {
        ^ ( __exl3_err prefix `trellis, suh and svh do not agree` )
    } {}
    ? | != % k 128 0 != % n 128 0 { ^ ( __exl3_err prefix `k and n must be multiples of 128 (the Hadamard blocks)` ) } {}
    : String mcg ( __exl3_name prefix `mcg` )
    : String mul1 ( __exl3_name prefix `mul1` )
    : i cb ? >= ( st_find_tensor st ( string_data mul1 ) ) 0 2 ? >= ( st_find_tensor st ( string_data mcg ) ) 0 1 0
    // the half-integer rates are mul1's alone (exllamav3 refuses others)
    ? & == % k2 2 1 != cb 2 { ^ ( __exl3_err prefix `a half-integer bitrate needs the mul1 codebook` ) } {}
    : GkBBuf q ( gk_bbuf_new kit . tt nbytes )
    ? ( gk_bbuf_upload_bytes kit q ( st_tensor_bytes st tt ) ) {} { ^ ( __exl3_err prefix `trellis upload failed` ) }
    : ( Vec u ) sv ( vec_with_cap [u] * 2 + k n )
    ( __exl3_append sv ( st_tensor_bytes st ut ) )
    ( __exl3_append sv ( st_tensor_bytes st vt ) )
    : GkHBuf h ( gk_hbuf_new kit + k n F )
    ? ( gk_hbuf_upload_bytes kit h ( slice_from_vec [u] sv ) ) {} { ^ ( __exl3_err prefix `suh / svh upload failed` ) }
    : GkBuf lut ? == cb 2 . luts cb2 ? == cb 1 . luts cb1 . luts cb0
    ^ @ !LkW String { T @ LkW { + + LK_EXL3 * 100 cb k2 q lut h aux } }
}

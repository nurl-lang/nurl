// gput_f32_lora_dump.nu — bit dump for the f32 LoRA oracle. Builds the
// shared Qwen2-style block (seed 42, nonzero B), captures it in FLOAT32
// device replay (gput_capture_dt dtype=1), runs forward+backward ON THE
// DEVICE, and prints every input pool + the f32 loss + all 14 adapter
// gradients (downloaded from the device) as f64 bit patterns.
// gput_f32_lora_oracle.sh rebuilds the identical graph in torch.float32 and
// compares within f32 tolerance — pinning the f32 DEVICE numerics to an
// external reference (the existing lora_oracle only checks the f64 CPU tape).
// SKIPs (prints "SKIP") without a compute backend.

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/floatbits.nu`
$ `src/grad.nu`
$ `src/gput.nu`
$ `tests/lora_block.nu`
$ `deps/tensor/src/tensor.nu`
$ `deps/gpu/src/gpu.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`

@ dumpv s name ( Vec f ) v → v {
    ( nurl_print name )
    : ~ i k 0
    ~ < k ( vec_len [f] v ) {
        ( nurl_print ` ` )
        ( nurl_print ( nurl_str_int ( f64_to_bits ( _tf v k ) ) ) )
        = k + k 1
    }
    ( nurl_print `\n` )
}

@ main → i {
    : *GpuKit kit ( gk_open 0 )
    ? ( gk_ok kit ) {} {
        ( nurl_print `SKIP no backend\n` )
        ( gk_close kit )
        ^ 0
    }
    : Blk bl ( blk_new 42 F )
    ( dumpv `x` . bl x )
    ( dumpv `wq` . bl wq ) ( dumpv `bq` . bl bq )
    ( dumpv `wk` . bl wk ) ( dumpv `bk` . bl bk )
    ( dumpv `wv` . bl wv ) ( dumpv `bv` . bl bv )
    ( dumpv `wo` . bl wo )
    ( dumpv `wg` . bl wg ) ( dumpv `wu` . bl wu ) ( dumpv `wd` . bl wd )
    ( dumpv `n1` . bl n1 ) ( dumpv `n2` . bl n2 ) ( dumpv `nf` . bl nf )
    ( dumpv `wout` . bl wout )
    ( dumpv `cosv` . bl cosv ) ( dumpv `sinv` . bl sinv )
    ( dumpv `mask` . bl mask ) ( dumpv `onehot` . bl onehot )
    ( dumpv `la` . bl la ) ( dumpv `lb` . bl lb )
    : *GTape tp ( tape_new )
    : *u pav ( nurl_alloc * 7 8 )
    : *u pbv ( nurl_alloc * 7 8 )
    : GVar loss ( build_block tp bl pav pbv )
    // capture + run the whole block in FLOAT32 on the device
    : *GProg pg ( gput_capture_dt kit tp loss 1 )
    ? ( gput_ok pg ) {} {
        ( nurl_print `SKIP capture failed\n` )
        ^ 0
    }
    : b _f ( gput_forward pg )
    : b _b ( gput_backward pg )
    ( nurl_print `loss ` )
    ( nurl_print ( nurl_str_int ( f64_to_bits ( gput_loss pg ) ) ) )
    ( nurl_print `\n` )
    : ~ i k 0
    ~ < k 7 {
        : GVar pa @ GVar { ( nurl_peek pav k ) }
        : GVar pb @ GVar { ( nurl_peek pbv k ) }
        : Tensor ta ( gvar_value tp pa )
        : i na ( vec_len [f] . ta data )
        : ( Vec f ) ga ( vec_with_cap [f] na )
        : ~ i z 0
        ~ < z na { ( vec_push [f] ga 0.0 ) = z + z 1 }
        : b _ga ( gput_grad pg pa ga )
        : Tensor tb ( gvar_value tp pb )
        : i nb ( vec_len [f] . tb data )
        : ( Vec f ) gb ( vec_with_cap [f] nb )
        = z 0
        ~ < z nb { ( vec_push [f] gb 0.0 ) = z + z 1 }
        : b _gb ( gput_grad pg pb gb )
        : String an ( string_from `gA` )
        ( string_push_str an ( nurl_str_int k ) )
        ( dumpv ( string_data an ) ga )
        ( string_free an )
        : String bn ( string_from `gB` )
        ( string_push_str bn ( nurl_str_int k ) )
        ( dumpv ( string_data bn ) gb )
        ( string_free bn )
        ( vec_free [f] ga ) ( vec_free [f] gb )
        = k + k 1
    }
    ( nurl_free pav ) ( nurl_free pbv )
    ( gput_free pg )
    ( tape_free tp )
    ( blk_free bl )
    ( gk_close kit )
    ^ 0
}

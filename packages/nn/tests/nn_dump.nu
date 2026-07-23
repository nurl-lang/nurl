// nn_dump.nu — bit dump for the nn PyTorch oracle (nn_oracle.sh). Builds the
// shared block (seed 42, nonzero B) from nn primitives, runs backward, and
// prints every input pool, the loss, and all 14 adapter gradients as f64 bit
// patterns — nn_oracle.sh rebuilds the identical graph in torch float64.

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/floatbits.nu`
$ `src/nn.nu`
$ `deps/grad/src/grad.nu`
$ `tests/nn_block.nu`
$ `deps/tensor/src/tensor.nu`

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
    : b bok ( backward tp loss )
    ? bok {} { ( nurl_print `BACKWARD FAILED\n` ) ^ 1 }
    ( nurl_print `loss ` )
    ( nurl_print ( nurl_str_int ( f64_to_bits ( g_scalar tp loss ) ) ) )
    ( nurl_print `\n` )
    : ~ i k 0
    ~ < k 7 {
        : GVar pa @ GVar { ( nurl_peek pav k ) }
        : GVar pb @ GVar { ( nurl_peek pbv k ) }
        : Tensor ga ( grad_of tp pa )
        : Tensor gb ( grad_of tp pb )
        : String na ( string_from `gA` )
        ( string_push_str na ( nurl_str_int k ) )
        ( dumpv ( string_data na ) . ga data )
        ( string_free na )
        : String nb ( string_from `gB` )
        ( string_push_str nb ( nurl_str_int k ) )
        ( dumpv ( string_data nb ) . gb data )
        ( string_free nb )
        = k + k 1
    }
    ( nurl_free pav ) ( nurl_free pbv )
    ( tape_free tp )
    ( blk_free bl )
    ^ 0
}

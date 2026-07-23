// nn_block_test.nu — torch-free gate for the composed block: it builds from
// nn primitives, forwards to a sane loss, backward runs, and every adapter
// gradient is finite and not all-zero. The exact numerics are pinned by
// nn_oracle.sh (PyTorch f64, loss 3e-16 / grads 1e-13).
//
//   NURL_STDLIB=<repo> ../../nurl.sh tests/nn_block_test.nu /tmp/nb && /tmp/nb

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `src/nn.nu`
$ `deps/grad/src/grad.nu`
$ `tests/nn_block.nu`
$ `deps/tensor/src/tensor.nu`

: ~ i g_pass 0

: ~ i g_fail 0

@ check b ok s label → v {
    ? ok { ( nurl_print `  ok ` ) = g_pass + g_pass 1 } { ( nurl_print `  FAIL ` ) = g_fail + g_fail 1 }
    ( nurl_print label ) ( nurl_print `\n` )
}

@ main → i {
    : Blk bl ( blk_new 42 F )
    : *GTape tp ( tape_new )
    : *u pav ( nurl_alloc * 7 8 )
    : *u pbv ( nurl_alloc * 7 8 )
    : GVar loss ( build_block tp bl pav pbv )
    ( check ( tape_ok tp ) `block builds (tape healthy)` )
    : f l ( g_scalar tp loss )
    ( check & > l 0.1 < l 10.0 `CE loss sane (0.1 < loss < 10)` )
    ( check ( backward tp loss ) `backward runs` )
    // every adapter gradient finite and not all-zero
    : ~ b allok T
    : ~ i k 0
    ~ < k 7 {
        : GVar pa @ GVar { ( nurl_peek pav k ) }
        : GVar pb @ GVar { ( nurl_peek pbv k ) }
        : Tensor ga ( grad_of tp pa )
        : Tensor gb ( grad_of tp pb )
        : ~ b nza F
        : ~ i j 0
        ~ < j ( vec_len [f] . ga data ) {
            : f gv ( _tf . ga data j )
            ? != gv gv { = allok F } {}
            ? != gv 0.0 { = nza T } {}
            = j + j 1
        }
        ? nza {} { = allok F }
        // B side: zero-initialised, but after one backward the A-side path
        // makes dL/dB nonzero too
        : ~ b nzb F
        = j 0
        ~ < j ( vec_len [f] . gb data ) {
            : f gv ( _tf . gb data j )
            ? != gv gv { = allok F } {}
            ? != gv 0.0 { = nzb T } {}
            = j + j 1
        }
        ? nzb {} { = allok F }
        = k + k 1
    }
    ( check allok `all 14 adapter gradients finite and non-zero` )
    ( nurl_free pav ) ( nurl_free pbv )
    ( tape_free tp )
    ( blk_free bl )
    ( nurl_print `nn_block_test: ` ) ( nurl_print_int g_pass )
    ( nurl_print ` passed, ` ) ( nurl_print_int g_fail ) ( nurl_print ` failed\n` )
    ^ ? > g_fail 0 1 0
}

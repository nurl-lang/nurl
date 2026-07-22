// emitc_dump.nu — build a scalar per-example loss on the tape, print the
// emitted CUDA-C grad() (host-compilable form) AND the tape's own
// gradients for a probe (x, v, p) as f64 bits. tests/emitc_oracle.sh
// compiles the emitted C with gcc -ffp-contract=off and asserts the C
// gradients equal the tape's BIT FOR BIT.
//
// Model (touches every scalar op): with xf = (double)x, target v,
//   z  = p0·xf + p1
//   h  = tanh(z) + sigmoid(p2·xf) + relu(p1 - v)
//   q  = log(exp(h) + sqrt(p0·p0 + 1.5)) / (p2·p2 + 1.0)
//   L  = mean((q - v)²)   (sum/mean pass through at [1])

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/floatbits.nu`
$ `src/grad.nu`
$ `src/emitc.nu`
$ `deps/tensor/src/tensor.nu`

@ sc * GTape tp f v b param → GVar {
    : ( Vec f ) d ( vec_new [f] )
    ( vec_push [f] d v )
    : ( Vec i ) s ( vec_new [i] )
    ( vec_push [i] s 1 )
    : Tensor t ( tensor_from_data TE_F64 s d )
    : GVar o ? param ( grad_param tp t ) ( grad_const tp t )
    ( tensor_free t ) ( vec_free [f] d )
    ^ o
}

@ main → i {
    : f XPROBE 3.0
    : f VPROBE 0.7
    : f P0 0.31
    : f P1 -0.42
    : f P2 0.9
    : *GTape tp ( tape_new )
    : GVar p0 ( sc tp P0 T )
    : GVar p1 ( sc tp P1 T )
    : GVar p2 ( sc tp P2 T )
    : GVar xf ( sc tp XPROBE F )
    : GVar vv ( sc tp VPROBE F )
    : GVar z ( g_add tp ( g_mul tp p0 xf ) p1 )
    : GVar h ( g_add tp ( g_add tp ( g_tanh tp z ) ( g_sigmoid tp ( g_mul tp p2 xf ) ) )
    ( g_relu tp ( g_sub tp p1 vv ) ) )
    : GVar num ( g_log tp ( g_add tp ( g_exp tp h ) ( g_sqrt tp ( g_adds tp ( g_mul tp p0 p0 ) 1.5 ) ) ) )
    : GVar q ( g_div tp num ( g_adds tp ( g_mul tp p2 p2 ) 1.0 ) )
    : GVar e ( g_sub tp q vv )
    : GVar loss ( g_mean tp ( g_mul tp e e ) )
    : b bok ( backward tp loss )
    ? bok {} { ( nurl_print `BACKWARD FAILED\n` ) ^ 1 }
    : ( Vec i ) pids ( vec_new [i] )
    ( vec_push [i] pids . p0 id ) ( vec_push [i] pids . p1 id ) ( vec_push [i] pids . p2 id )
    : ( Vec i ) lids ( vec_new [i] )
    ( vec_push [i] lids . xf id ) ( vec_push [i] lids . vv id )
    : ( Vec s ) lexprs ( vec_new [s] )
    ( vec_push [s] lexprs `((double)x)` )
    ( vec_push [s] lexprs `v` )
    : String src ( string_new )
    ? ( gemit_cuda_grad tp loss pids lids lexprs T src ) {} { ( nurl_print `EMIT FAILED\n` ) ^ 1 }
    ( nurl_print `===SRC===\n` )
    ( nurl_print ( string_data src ) )
    ( nurl_print `===GRADS===\n` )
    : ~ i j 0
    ~ < j 3 {
        : GVar pv @ GVar { ( _ti pids j ) }
        : Tensor g ( grad_of tp pv )
        ( nurl_print ( nurl_str_int ( f64_to_bits ( _tf . g data 0 ) ) ) )
        ( nurl_print `\n` )
        = j + j 1
    }
    ( nurl_print `===PROBE===\n` )
    ( nurl_print ( nurl_str_int ( f64_to_bits XPROBE ) ) ) ( nurl_print `\n` )
    ( nurl_print ( nurl_str_int ( f64_to_bits VPROBE ) ) ) ( nurl_print `\n` )
    ( nurl_print ( nurl_str_int ( f64_to_bits P0 ) ) ) ( nurl_print `\n` )
    ( nurl_print ( nurl_str_int ( f64_to_bits P1 ) ) ) ( nurl_print `\n` )
    ( nurl_print ( nurl_str_int ( f64_to_bits P2 ) ) ) ( nurl_print `\n` )
    ( string_free src )
    ( vec_free [i] pids ) ( vec_free [i] lids ) ( vec_free [s] lexprs )
    ( tape_free tp )
    ^ 0
}

// packages/onnx/src/runtime.nu — the graph executor.
//
// Walks the ONNX graph in node order (ONNX guarantees topological order),
// keeping every intermediate tensor resident on the GPU. Initializers and
// the input are uploaded once; each node dispatches to a gpukit dev-layer
// kernel (gkd_* — the SAME dtype-generic kernel library the tensor
// package's DTensor uses; onnx carries no kernel sources of its own); the
// named output is downloaded at the end. A value map (name → device
// tensor) threads activations between nodes. Kernels compile lazily and
// are cached by gpukit (in-process by name, on disk by source hash), and
// launches chain on the stream with ONE device sync at the end of the walk.
//
// Tensors are N-D (shape vector); the dense path reads dims 0,1 as M,K and
// the conv path reads NCHW from dims 1,2,3 (batch N is assumed 1).

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `deps/gpu/src/gpu.nu`
$ `deps/gpukit/src/devops.nu`
$ `model.nu`

// A device-resident tensor: name, CUdeviceptr (i64), shape, element count.
: RTensor { String name i dptr ( Vec i ) shape i nelem }

// Engine.g BORROWS the kit's device handle (gk_close releases it).
: Engine { Gpu g * GpuKit kit ( Vec RTensor ) vals OGraph graph b ok ( Vec i ) owned b graph_set }

// GkBuf views over an RTensor's device allocation, for the gkd_* kernels.
// Everything on the value map is f32 except the raw token input and ArgMax
// outputs, which the call sites view as i64 explicitly.
@ __rt_fbuf RTensor t → GkBuf { ^ @ GkBuf { . t dptr . t nelem GK_F32 } }

@ __rt_ibuf RTensor t → GkBuf { ^ @ GkBuf { . t dptr . t nelem GK_I64 } }

@ __rt_op_fail s op → v {
    ( nurl_eprint `[onnx] kernel failed: ` )
    ( nurl_eprint op )
    ( nurl_eprint `\n` )
}

@ streq2 s a s b → b { ^ != ( nurl_str_eq a b ) 0 }

@ ceil_div i a i b → i { ^ / + a - b 1 b }

// ── initializer metadata (int64 shape/size tensors stay host-side) ──
& `c` @ nurl_peek_f32 *u base i idx → f

@ __init_tensor * Engine e s name → OTensor {
    : OGraph g . e graph
    : i idx ( graph_find_init g name )
    ? < idx 0 { ^ @ OTensor { ( string_new ) ( vec_new [i] ) 0 0 0 } } {}
    ?? ( vec_get [OTensor] . g inits idx ) { T t → ^ t F _ → ^ @ OTensor { ( string_new ) ( vec_new [i] ) 0 0 0 } }
}

@ __init_i64 * Engine e s name i k → i {  // k-th value of an INT64 init
    : OTensor t ( __init_tensor e name )
    ? == . t host 0 { ^ 0 } { ^ ( nurl_peek # *u . t host k ) }
}

@ __init_i64_len * Engine e s name → i { : OTensor t ( __init_tensor e name ) ^ . t nelem }

@ __init_f32 * Engine e s name i k → f {  // k-th value of a FLOAT init
    : OTensor t ( __init_tensor e name )
    ? == . t host 0 { ^ 0.0 } { ^ ( nurl_peek_f32 # *u . t host k ) }
}

@ __prod ( Vec i ) v → i {
    : ~ i p 1
    : ~ i k 0
    ~ < k ( vec_len [i] v ) { ?? ( vec_get [i] v k ) { T d → = p * p d F _ → {} } = k + k 1 }
    ^ p
}

@ __dim_at ( Vec i ) v i ax → i { ?? ( vec_get [i] v ax ) { T d → ^ d F _ → ^ 1 } }

@ rt_dim RTensor t i ax → i { ^ ( __dim_at . t shape ax ) }

// Open a device. Kernels compile lazily on first use (gpukit caches them
// in-process by name and on disk by source hash and architecture).
@ rt_open i ordinal → *Engine {
    : *Engine e # *Engine ( nurl_alloc Z Engine )
    = . e kit ( gk_open ordinal )
    = . e g . . e kit gpu
    = . e vals ( vec_new [RTensor] )
    = . e graph @ OGraph { ( vec_new [ONode] ) ( vec_new [OTensor] ) ( string_new ) ( string_new ) ( string_new ) }
    = . e ok ( gk_ok . e kit )
    = . e owned ( vec_new [i] )
    = . e graph_set F
    ^ e
}

// Install the caller's graph on the engine. The placeholder OGraph that
// rt_open allocated is freed on the first install; caller graphs are
// BORROWED (the engine never frees them).
@ _rt_set_graph * Engine e OGraph g → v {
    ? . e graph_set {} { ( graph_free . e graph ) }
    = . e graph g
    = . e graph_set T
}

// Record a device allocation so rt_reset can free it. Aliased tensors
// (Reshape/Split share or offset an existing buffer) are NOT recorded — only
// the real gpu_alloc base pointers, so reset frees each allocation exactly
// once with no double-free / free-of-non-base.
@ rt_own * Engine e i dptr → i {
    ( vec_push [i] . e owned dptr )
    ^ dptr
}

// Free every device buffer allocated during the previous run and clear the
// value map. Lets one Engine serve many forward passes (e.g. one text prompt
// per call) without leaking the model's weights + activations each time.
@ rt_reset * Engine e → v {
    : ( Vec i ) own . e owned
    : ~ i k 0
    ~ < k ( vec_len [i] own ) {
        ?? ( vec_get [i] own k ) { T d → ? > d 0 { ( gpu_free @ GpuBuffer { d 0 } ) } {} F _ → {} }
        = k + k 1
    }
    ( vec_free [i] own )
    = . e owned ( vec_new [i] )
    : ( Vec RTensor ) vs . e vals
    : ~ i j 0
    ~ < j ( vec_len [RTensor] vs ) {
        ?? ( vec_get [RTensor] vs j ) {
            T t → { ( string_free . t name ) ( vec_free [i] . t shape ) }
            F _ → {}
        }
        = j + j 1
    }
    ( vec_free [RTensor] vs )
    = . e vals ( vec_new [RTensor] )
}

@ rt_ok * Engine e → b { ^ . e ok }

@ rt_name * Engine e → s { ^ ( gpu_name . e g ) }

// Register a device tensor under `name` with an explicit shape vector.
@ rt_put * Engine e s name i dptr ( Vec i ) shape → v {
    ( vec_push [RTensor] . e vals @ RTensor { ( string_from name ) dptr shape ( __prod shape ) } )
}

@ __shape2 i a i b → ( Vec i ) { : ( Vec i ) v ( vec_new [i] ) ( vec_push [i] v a ) ( vec_push [i] v b ) ^ v }

@ __shape4 i a i b i c i d → ( Vec i ) {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v a ) ( vec_push [i] v b ) ( vec_push [i] v c ) ( vec_push [i] v d ) ^ v
}

@ rt_find * Engine e s name → i {
    : ( Vec RTensor ) vs . e vals
    : ~ i k 0
    ~ < k ( vec_len [RTensor] vs ) {
        ?? ( vec_get [RTensor] vs k ) { T t → ? ( streq2 ( string_data . t name ) name ) { ^ k } {} F _ → {} }
        = k + k 1
    }
    ^ - 0 1
}

@ rt_at * Engine e i idx → RTensor {
    ?? ( vec_get [RTensor] . e vals idx ) { T t → ^ t F _ → ^ @ RTensor { ( string_new ) 0 ( vec_new [i] ) 0 } }
}
// Input name of a node (k-th), as an `s`.
@ __in * Engine e ONode n i k → RTensor {
    : ( Vec String ) ins . n inputs
    : i idx ( rt_find e ( string_data ?? ( vec_get [String] ins k ) { T x → x F _ → ( string_new ) } ) )
    ^ ( rt_at e idx )
}

@ __out_name ONode n → s {
    ^ ( string_data ?? ( vec_get [String] . n outputs 0 ) { T x → x F _ → ( string_new ) } )
}

@ __rt_in_name ONode n i k → s {
    ^ ( string_data ?? ( vec_get [String] . n inputs k ) { T x → x F _ → ( string_new ) } )
}

// ── host-side INT64 tensors ───────────────────────────────────────
// The shape-arithmetic chains a torch export leaves behind —
// Shape → Gather/Unsqueeze/Concat/Cast/Slice → a Resize `sizes` input —
// run on the HOST: with a static input shape they are constants, and
// three-element i64 tensors have no business on the device. A host-int
// tensor lives in the SAME value map as an RTensor whose dptr is the
// RT_HOSTI sentinel and whose VALUES sit in the `shape` vector, so
// rt_reset frees it like any other entry and the ready gate's rt_find
// keeps working unchanged.
: i RT_HOSTI - 0 1

@ __hi_put * Engine e s name ( Vec i ) vals → v {
    ( rt_put e name RT_HOSTI vals )
}

// The named value as a host int vector: a host tensor's values, else an
// INT64 initializer's, else empty. The returned vec is FRESH (caller
// frees). Device tensors yield empty — float weights never alias an
// INT64 name — so "non-empty" doubles as "this is host data".
@ __hi_vals * Engine e s name → ( Vec i ) {
    : ( Vec i ) out ( vec_new [i] )
    ? == ( nurl_str_len name ) 0 { ^ out } {}
    : i idx ( rt_find e name )
    ? >= idx 0 {
        : RTensor t ( rt_at e idx )
        ? == . t dptr RT_HOSTI {
            : ~ i k 0
            ~ < k ( vec_len [i] . t shape ) {
                ( vec_push [i] out ?? ( vec_get [i] . t shape k ) { T v → v F _ → 0 } )
                = k + k 1
            }
        } {}
        ^ out
    } {}
    : i nl ( __init_i64_len e name )
    : ~ i k 0
    ~ < k nl { ( vec_push [i] out ( __init_i64 e name k ) ) = k + k 1 }
    ^ out
}

// Execute a node entirely on the host when its data is host-int. Returns
// T when the node was consumed (its output registered, or deliberately
// dropped), F when the device dispatch should have it.
@ __rt_host_step * Engine e ONode n → b {
    : s op ( string_data . n op_type )
    ? ( streq2 op `Constant` ) {
        // The payload's INT64 values were folded into the `value`
        // attribute's ints at parse time; a float Constant (the empty
        // roi/scales of a Resize) registers as an empty host tensor.
        : ( Vec i ) vals ( vec_new [i] )
        : i nv ( node_attr_ints_len n `value` )
        : ~ i k 0
        ~ < k nv { ( vec_push [i] vals ( node_attr_int_at n `value` k 0 ) ) = k + k 1 }
        ( __hi_put e ( __out_name n ) vals )
        ^ T
    } {}
    ? ( streq2 op `Shape` ) {
        : i idx ( rt_find e ( __rt_in_name n 0 ) )
        ? < idx 0 { ^ T } {}
        : RTensor X ( rt_at e idx )
        : ( Vec i ) vals ( vec_new [i] )
        ? == . X dptr RT_HOSTI { ( vec_push [i] vals ( vec_len [i] . X shape ) ) } {
            : ~ i k 0
            ~ < k ( vec_len [i] . X shape ) {
                ( vec_push [i] vals ?? ( vec_get [i] . X shape k ) { T v → v F _ → 0 } )
                = k + k 1
            }
        }
        ( __hi_put e ( __out_name n ) vals )
        ^ T
    } {}
    ? | | ( streq2 op `Cast` ) ( streq2 op `Unsqueeze` ) ( streq2 op `Squeeze` ) {
        // Value-preserving on a flat int list (Cast only ever targets
        // INT64 in these chains; a 1-D unsqueeze/squeeze is shape-talk).
        : ( Vec i ) vals ( __hi_vals e ( __rt_in_name n 0 ) )
        ? == ( vec_len [i] vals ) 0 { ( vec_free [i] vals ) ^ F } {}
        ( __hi_put e ( __out_name n ) vals )
        ^ T
    } {}
    ? ( streq2 op `Gather` ) {
        : ( Vec i ) data ( __hi_vals e ( __rt_in_name n 0 ) )
        ? == ( vec_len [i] data ) 0 { ( vec_free [i] data ) ^ F } {}
        : ( Vec i ) idxs ( __hi_vals e ( __rt_in_name n 1 ) )
        : i dn ( vec_len [i] data )
        : ( Vec i ) vals ( vec_new [i] )
        : ~ i k 0
        ~ < k ( vec_len [i] idxs ) {
            : ~ i ix ?? ( vec_get [i] idxs k ) { T v → v F _ → 0 }
            ? < ix 0 { = ix + ix dn } {}
            ( vec_push [i] vals ?? ( vec_get [i] data ix ) { T v → v F _ → 0 } )
            = k + k 1
        }
        ( vec_free [i] data )
        ( vec_free [i] idxs )
        ( __hi_put e ( __out_name n ) vals )
        ^ T
    } {}
    ? ( streq2 op `Concat` ) {
        : ( Vec i ) first ( __hi_vals e ( __rt_in_name n 0 ) )
        ? == ( vec_len [i] first ) 0 { ( vec_free [i] first ) ^ F } {}
        : ( Vec i ) vals first
        : ~ i k 1
        ~ < k ( vec_len [String] . n inputs ) {
            : ( Vec i ) part ( __hi_vals e ( __rt_in_name n k ) )
            : ~ i j 0
            ~ < j ( vec_len [i] part ) {
                ( vec_push [i] vals ?? ( vec_get [i] part j ) { T v → v F _ → 0 } )
                = j + j 1
            }
            ( vec_free [i] part )
            = k + k 1
        }
        ( __hi_put e ( __out_name n ) vals )
        ^ T
    } {}
    ? ( streq2 op `Slice` ) {
        : ( Vec i ) data ( __hi_vals e ( __rt_in_name n 0 ) )
        ? == ( vec_len [i] data ) 0 { ( vec_free [i] data ) ^ F } {}
        : ( Vec i ) starts ( __hi_vals e ( __rt_in_name n 1 ) )
        : ( Vec i ) ends ( __hi_vals e ( __rt_in_name n 2 ) )
        : i dn ( vec_len [i] data )
        : ~ i s0 ?? ( vec_get [i] starts 0 ) { T v → v F _ → 0 }
        : ~ i e0 ?? ( vec_get [i] ends 0 ) { T v → v F _ → dn }
        ? < s0 0 { = s0 + s0 dn } {}
        ? < e0 0 { = e0 + e0 dn } {}
        ? > e0 dn { = e0 dn } {}
        : ( Vec i ) vals ( vec_new [i] )
        : ~ i k s0
        ~ < k e0 {
            ( vec_push [i] vals ?? ( vec_get [i] data k ) { T v → v F _ → 0 } )
            = k + k 1
        }
        ( vec_free [i] data )
        ( vec_free [i] starts )
        ( vec_free [i] ends )
        ( __hi_put e ( __out_name n ) vals )
        ^ T
    } {}
    ^ F
}

// Upload all graph initializers to the device as RTensors (full shape).
// Fresh copy of a shape vector — rt_put ADOPTS its shape argument (rt_reset
// frees it), so borrowed vectors (a graph init's dims) must be copied in.
@ __shape_copy_rt ( Vec i ) src → ( Vec i ) {
    : i n ( vec_len [i] src )
    : ( Vec i ) o ( vec_with_cap [i] ? > n 0 { n } { 1 } )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [i] src k ) { T v → { ( vec_push [i] o v ) } F _ → {} }
        = k + k 1
    }
    ^ o
}

@ rt_load_inits * Engine e OGraph g → v {
    : ( Vec OTensor ) inits . g inits
    : ~ i k 0
    ~ < k ( vec_len [OTensor] inits ) {
        ?? ( vec_get [OTensor] inits k ) {
            T t → {
                // INT64 tensors (shapes/sizes/anchor grids) stay host-side as
                // metadata — read via __init_i64; only FLOAT weights go to GPU.
                ? & != . t dtype 7 != . t host 0 {
                    : i n . t nelem
                    : GpuBuffer buf ( gpu_alloc . e g * n 4 )
                    ( rt_own e . buf dptr )
                    ( gpu_upload buf # *u . t host )
                    ( rt_put e ( string_data . t name ) . buf dptr ( __shape_copy_rt . t dims ) )
                } {}
            } F _ → {}
        }
        = k + k 1
    }
}

// Allocate a fresh device tensor with `shape`, register under `name`,
// return its dptr.
@ rt_alloc_out * Engine e s name ( Vec i ) shape → i {
    : GpuBuffer buf ( gpu_alloc . e g * ( __prod shape ) 4 )
    ( rt_own e . buf dptr )
    ( rt_put e name . buf dptr shape )
    ^ . buf dptr
}

// ── op handlers ───────────────────────────────────────────────────
@ rt_gemm * Engine e ONode n → v {
    : RTensor A ( __in e n 0 )
    : RTensor B ( __in e n 1 )
    : i transB ( node_attr_i n `transB` 0 )
    : f alpha ( node_attr_f n `alpha` 1.0 )
    : f beta ( node_attr_f n `beta` 1.0 )
    : i M ( rt_dim A 0 )
    : i K ( rt_dim A 1 )
    : i N ? != transB 0 ( rt_dim B 0 ) ( rt_dim B 1 )
    : ~ i hasb 0
    : ~ GkBuf cb ( __rt_fbuf A )
    ? > ( vec_len [String] . n inputs ) 2 { : RTensor C ( __in e n 2 ) = cb ( __rt_fbuf C ) = hasb 1 } {}
    : i yd ( rt_alloc_out e ( __out_name n ) ( __shape2 M N ) )
    : GkBuf yb @ GkBuf { yd * M N GK_F32 }
    ? ( gkd_gemm . e kit yb ( __rt_fbuf A ) ( __rt_fbuf B ) cb hasb M N K alpha beta transB ) {} { ( __rt_op_fail `Gemm` ) }
}

@ rt_relu * Engine e ONode n → v {
    : RTensor X ( __in e n 0 )
    : i yd ( rt_alloc_out e ( __out_name n ) ( __shape_copy_rt . X shape ) )
    : GkBuf yb @ GkBuf { yd . X nelem GK_F32 }
    ? ( gkd_relu . e kit yb ( __rt_fbuf X ) ) {} { ( __rt_op_fail `Relu` ) }
}

@ rt_conv * Engine e ONode n → v {
    : RTensor X ( __in e n 0 )
    : RTensor W ( __in e n 1 )
    : i Cin ( rt_dim X 1 )
    : i H ( rt_dim X 2 )
    : i Wd ( rt_dim X 3 )
    : i Cout ( rt_dim W 0 )
    : i kh ( rt_dim W 2 )
    : i kw ( rt_dim W 3 )
    : i sh ( node_attr_int_at n `strides` 0 1 )
    : i sw ( node_attr_int_at n `strides` 1 1 )
    // dilation stretches the EFFECTIVE kernel: ek = (k−1)·d + 1. U²-Net's
    // RSU4F runs 3×3 at d = 2/4/8; ignoring the attribute silently grows
    // every such map (pad 2, effective kernel still read as 3).
    : i dh ( node_attr_int_at n `dilations` 0 1 )
    : i dw ( node_attr_int_at n `dilations` 1 1 )
    : i ekh + * - kh 1 dh 1
    : i ekw + * - kw 1 dw 1
    : s ap ( node_attr_s n `auto_pad` `NOTSET` )
    : ~ i OH ( ceil_div H sh )
    : ~ i OW ( ceil_div Wd sw )
    : ~ i ph 0
    : ~ i pw 0
    ? | ( streq2 ap `SAME_UPPER` ) ( streq2 ap `SAME_LOWER` ) {
        : i pht - + * - OH 1 sh ekh H
        : i pwt - + * - OW 1 sw ekw Wd
        = ph ? > pht 0 / pht 2 0
        = pw ? > pwt 0 / pwt 2 0
    } {
        = OH + / - + H * 2 ( node_attr_int_at n `pads` 0 0 ) ekh sh 1
        = OW + / - + Wd * 2 ( node_attr_int_at n `pads` 1 0 ) ekw sw 1
        = ph ( node_attr_int_at n `pads` 0 0 )
        = pw ( node_attr_int_at n `pads` 1 0 )
    }
    : ~ i hasB 0
    : ~ GkBuf bb ( __rt_fbuf X )
    ? > ( vec_len [String] . n inputs ) 2 { : RTensor B ( __in e n 2 ) = bb ( __rt_fbuf B ) = hasB 1 } {}
    : i yd ( rt_alloc_out e ( __out_name n ) ( __shape4 1 Cout OH OW ) )
    : GkBuf yb @ GkBuf { yd * * Cout OH OW GK_F32 }
    ? ( gkd_conv2d_dil . e kit yb ( __rt_fbuf X ) ( __rt_fbuf W ) bb hasB Cin H Wd Cout kh kw OH OW ph pw sh sw dh dw ) {} { ( __rt_op_fail `Conv` ) }
}

// Transposed convolution (ConvTranspose). Weight is [Cin, Cout, kh, kw].
// Output size per ONNX: O = stride·(I−1) + output_padding + (k−1)·dil+1
//   − pad_begin − pad_end. The seg Proto upsample is k2/s2/p0 → O = 2·I.
@ rt_convtranspose * Engine e ONode n → v {
    : RTensor X ( __in e n 0 )
    : RTensor W ( __in e n 1 )
    : i Cin ( rt_dim X 1 )
    : i H ( rt_dim X 2 )
    : i Wd ( rt_dim X 3 )
    : i Cout ( rt_dim W 1 )
    : i kh ( rt_dim W 2 )
    : i kw ( rt_dim W 3 )
    : i sh ( node_attr_int_at n `strides` 0 1 )
    : i sw ( node_attr_int_at n `strides` 1 1 )
    : i phb ( node_attr_int_at n `pads` 0 0 )
    : i pwb ( node_attr_int_at n `pads` 1 0 )
    : i phe ( node_attr_int_at n `pads` 2 0 )
    : i pwe ( node_attr_int_at n `pads` 3 0 )
    : i oph ( node_attr_int_at n `output_padding` 0 0 )
    : i opw ( node_attr_int_at n `output_padding` 1 0 )
    : i OH - - + + * sh - H 1 oph kh phb phe
    : i OW - - + + * sw - Wd 1 opw kw pwb pwe
    : ~ i hasB 0
    : ~ GkBuf bb ( __rt_fbuf X )
    ? > ( vec_len [String] . n inputs ) 2 { : RTensor B ( __in e n 2 ) = bb ( __rt_fbuf B ) = hasB 1 } {}
    : i yd ( rt_alloc_out e ( __out_name n ) ( __shape4 1 Cout OH OW ) )
    : GkBuf yb @ GkBuf { yd * * Cout OH OW GK_F32 }
    ? ( gkd_convtranspose2d . e kit yb ( __rt_fbuf X ) ( __rt_fbuf W ) bb hasB Cin H Wd Cout kh kw OH OW phb pwb sh sw ) {} { ( __rt_op_fail `ConvTranspose` ) }
}

@ rt_maxpool * Engine e ONode n → v {
    : RTensor X ( __in e n 0 )
    : i C ( rt_dim X 1 )
    : i H ( rt_dim X 2 )
    : i Wd ( rt_dim X 3 )
    : i kh ( node_attr_int_at n `kernel_shape` 0 2 )
    : i kw ( node_attr_int_at n `kernel_shape` 1 2 )
    : i sh ( node_attr_int_at n `strides` 0 1 )
    : i sw ( node_attr_int_at n `strides` 1 1 )
    : s ap ( node_attr_s n `auto_pad` `NOTSET` )
    // ceil_mode rounds the output size UP, so a window that hangs off the
    // edge still yields an output row (U²-Net's odd feature sizes: 5→3).
    : i cm ( node_attr_i n `ceil_mode` 0 )
    : ~ i OH 0
    : ~ i OW 0
    : ~ i ph 0
    : ~ i pw 0
    ? | ( streq2 ap `SAME_UPPER` ) ( streq2 ap `SAME_LOWER` ) {
        = OH ( ceil_div H sh ) = OW ( ceil_div Wd sw )
        : i pht - + * - OH 1 sh kh H
        : i pwt - + * - OW 1 sw kw Wd
        = ph ? > pht 0 / pht 2 0
        = pw ? > pwt 0 / pwt 2 0
    } {
        // NOTSET: explicit pads [top,left,bottom,right] (begin = top/left)
        = ph ( node_attr_int_at n `pads` 0 0 )
        = pw ( node_attr_int_at n `pads` 1 0 )
        : i ex ? != cm 0 - sh 1 0
        : i ex2 ? != cm 0 - sw 1 0
        = OH + / + - + H * 2 ph kh ex sh 1
        = OW + / + - + Wd * 2 pw kw ex2 sw 1
    }
    : i yd ( rt_alloc_out e ( __out_name n ) ( __shape4 1 C OH OW ) )
    : GkBuf yb @ GkBuf { yd * * C OH OW GK_F32 }
    ? ( gkd_maxpool2d . e kit yb ( __rt_fbuf X ) C H Wd kh kw OH OW sh sw ph pw ) {} { ( __rt_op_fail `MaxPool` ) }
}

@ rt_batchnorm * Engine e ONode n → v {
    : RTensor X ( __in e n 0 )
    : RTensor sc ( __in e n 1 )
    : RTensor B ( __in e n 2 )
    : RTensor mn ( __in e n 3 )
    : RTensor vr ( __in e n 4 )
    : i C ( rt_dim X 1 )
    : i HW / . X nelem C
    : f eps ( node_attr_f n `epsilon` 0.00001 )
    : i yd ( rt_alloc_out e ( __out_name n ) ( __shape_copy_rt . X shape ) )
    : GkBuf yb @ GkBuf { yd . X nelem GK_F32 }
    ? ( gkd_batchnorm . e kit yb ( __rt_fbuf X ) ( __rt_fbuf sc ) ( __rt_fbuf B ) ( __rt_fbuf mn ) ( __rt_fbuf vr ) C HW eps ) {} { ( __rt_op_fail `BatchNormalization` ) }
}

@ rt_leakyrelu * Engine e ONode n → v {
    : RTensor X ( __in e n 0 )
    : f alpha ( node_attr_f n `alpha` 0.01 )
    : i yd ( rt_alloc_out e ( __out_name n ) ( __shape_copy_rt . X shape ) )
    : GkBuf yb @ GkBuf { yd . X nelem GK_F32 }
    ? ( gkd_leakyrelu . e kit yb ( __rt_fbuf X ) alpha ) {} { ( __rt_op_fail `LeakyRelu` ) }
}

@ rt_ndim RTensor t → i { ^ ( vec_len [i] . t shape ) }

@ rt_last RTensor t → i { ^ ( rt_dim t - ( rt_ndim t ) 1 ) }

// Binary op: 0=Mul 1=Add 2=Sub 3=Div. For commutative ops (Mul/Add) the
// larger input is the data and the smaller broadcasts (ONNX allows either
// order); Sub/Div keep `in0 op in1`. Broadcast mode is inferred from the
// operand element count: scalar, full, per-inner (a per-anchor stride
// vector), or per-channel.
@ rt_binop * Engine e ONode n i op → v {
    : RTensor a ( __in e n 0 )
    : RTensor b ( __in e n 1 )
    : b comm | == op 0 == op 1
    : RTensor X ? & comm < . a nelem . b nelem b a
    : RTensor B ? & comm < . a nelem . b nelem a b
    : i C ( rt_dim X 1 )
    : i inner ( rt_last X )
    : ~ i bmode 2
    : ~ i per 0
    ? == . B nelem 1 { = bmode 0 }
    ? == . B nelem . X nelem { = bmode 2 }
    ? == . B nelem inner { = bmode 3 = per inner }
    ? == . B nelem C { = bmode 1 = per / . X nelem C }
    // B is a trailing sub-block tiled over the leading dims (e.g. a [.,1,S,S]
    // attention mask added to [.,H,S,S] scores): out[i] = X[i] op B[i % |B|].
    ? & > . B nelem 0 == 0 % . X nelem . B nelem { = bmode 3 = per . B nelem }
    { = bmode 2 }
    // bmode → a stride table for the broadcast-elementwise kernel:
    //   0 scalar       view [n]        X stride 1      B stride 0
    //   2 full         view [n]        X stride 1      B stride 1
    //   1 per-channel  view [C, per]   X (per, 1)      B (1, 0)
    //   3 per-inner    view [n/p, p]   X (p, 1)        B (0, 1)
    : i nx . X nelem
    : s opname ? == op 0 { `mul` } { ? == op 1 { `add` } { ? == op 2 { `sub` } { `div` } } }
    : s opc ? == op 0 { `*` } { ? == op 1 { `+` } { ? == op 2 { `-` } { `/` } } }
    : ( Vec i ) od ( vec_new [i] )
    : ( Vec i ) ast ( vec_new [i] )
    : ( Vec i ) bst ( vec_new [i] )
    ? == bmode 0 {
        ( vec_push [i] od nx ) ( vec_push [i] ast 1 ) ( vec_push [i] bst 0 )
    } {
        ? == bmode 2 {
            ( vec_push [i] od nx ) ( vec_push [i] ast 1 ) ( vec_push [i] bst 1 )
        } {
            ? == bmode 1 {
                ( vec_push [i] od C ) ( vec_push [i] od per )
                ( vec_push [i] ast per ) ( vec_push [i] ast 1 )
                ( vec_push [i] bst 1 ) ( vec_push [i] bst 0 )
            } {
                ( vec_push [i] od / nx per ) ( vec_push [i] od per )
                ( vec_push [i] ast per ) ( vec_push [i] ast 1 )
                ( vec_push [i] bst 0 ) ( vec_push [i] bst 1 )
            }
        }
    }
    : i yd ( rt_alloc_out e ( __out_name n ) ( __shape_copy_rt . X shape ) )
    : GkBuf yb @ GkBuf { yd nx GK_F32 }
    ? ( gkd_ew_bc . e kit opname opc yb ( __rt_fbuf X ) ( __rt_fbuf B ) od ast bst ) {} { ( __rt_op_fail `Mul/Add/Sub/Div` ) }
    ( vec_free [i] od )
    ( vec_free [i] ast )
    ( vec_free [i] bst )
}

@ rt_sigmoid * Engine e ONode n → v {
    : RTensor X ( __in e n 0 )
    : i yd ( rt_alloc_out e ( __out_name n ) ( __shape_copy_rt . X shape ) )
    : GkBuf yb @ GkBuf { yd . X nelem GK_F32 }
    ? ( gkd_sigmoid . e kit yb ( __rt_fbuf X ) ) {} { ( __rt_op_fail `Sigmoid` ) }
}

// Reshape: pure reinterpret (data is contiguous) → alias the input buffer
// under the output name with the new shape. Shape comes from the INT64
// initializer input[1]; a -1 entry is inferred, 0 copies the input dim.
@ rt_reshape * Engine e ONode n → v {
    : RTensor X ( __in e n 0 )
    : s shp_name ( string_data ?? ( vec_get [String] . n inputs 1 ) { T x → x F _ → ( string_new ) } )
    : i nd ( __init_i64_len e shp_name )
    : ( Vec i ) ns ( vec_new [i] )
    : ~ i prod 1
    : ~ i negat - 0 1
    : ~ i k 0
    ~ < k nd {
        : ~ i d ( __init_i64 e shp_name k )
        ? == d 0 { = d ( rt_dim X k ) } {}
        ? == d - 0 1 { = negat k ( vec_push [i] ns - 0 1 ) } { = prod * prod d ( vec_push [i] ns d ) }
        = k + k 1
    }
    ? >= negat 0 { ( vec_set [i] ns negat / . X nelem prod ) } {}
    ( rt_put e ( __out_name n ) . X dptr ns )
}

// Resize (nearest, integer upscale). Scales come from the FLOAT init
// input[2] = [1,1,sh,sw].
// Slice along ONE axis, unit step, bounds from int64 initializers
// (inputs: data, starts, ends, axes[, steps]) — the shape torch 2.12 /
// onnxsim emit for channel splits (older exports used Split, which has
// its own handler). Negative axes normalise; ends clamp to the dim.
@ rt_slice * Engine e ONode n → v {
    : RTensor X ( __in e n 0 )
    : i nd0 ( rt_ndim X )
    : s st_name ( string_data ?? ( vec_get [String] . n inputs 1 ) { T x → x F _ → ( string_new ) } )
    : s en_name ( string_data ?? ( vec_get [String] . n inputs 2 ) { T x → x F _ → ( string_new ) } )
    : ~ i axis 1
    ? > ( vec_len [String] . n inputs ) 3 {
        : s ax_name ( string_data ?? ( vec_get [String] . n inputs 3 ) { T x → x F _ → ( string_new ) } )
        = axis ( __init_i64 e ax_name 0 )
    } {}
    ? < axis 0 { = axis + axis nd0 } {}
    : ~ i step 1
    ? > ( vec_len [String] . n inputs ) 4 {
        : s sp_name ( string_data ?? ( vec_get [String] . n inputs 4 ) { T x → x F _ → ( string_new ) } )
        = step ( __init_i64 e sp_name 0 )
    } {}
    ? | != step 1 > ( __init_i64_len e st_name ) 1 {
        ( nurl_eprint `[onnx] Slice: only single-axis unit-step supported\n` )
    } {
        : i dim_ax ( rt_dim X axis )
        : ~ i sbeg ( __init_i64 e st_name 0 )
        : ~ i send ( __init_i64 e en_name 0 )
        ? < sbeg 0 { = sbeg + sbeg dim_ax } {}
        ? < send 0 { = send + send dim_ax } {}
        ? > send dim_ax { = send dim_ax } {}
        : i sz - send sbeg
        : ~ i outer 1
        : ~ i j 0
        ~ < j axis { = outer * outer ( rt_dim X j ) = j + j 1 }
        : ~ i inner 1
        : ~ i m + axis 1
        ~ < m nd0 { = inner * inner ( rt_dim X m ) = m + m 1 }
        : ( Vec i ) os ( vec_new [i] )
        : ~ i d 0
        ~ < d nd0 { ( vec_push [i] os ? == d axis sz ( rt_dim X d ) ) = d + d 1 }
        : i prodos ( __prod os )
        : i yd ( rt_alloc_out e ( __out_name n ) os )
        : GkBuf yb @ GkBuf { yd prodos GK_F32 }
        ? ( gkd_slice_ax . e kit yb ( __rt_fbuf X ) outer sz inner dim_ax sbeg ) {} { ( __rt_op_fail `Slice` ) }
    }
}

@ rt_resize * Engine e ONode n → v {
    : RTensor X ( __in e n 0 )
    : i C ( rt_dim X 1 )
    : i H ( rt_dim X 2 )
    : i W ( rt_dim X 3 )
    // The output size: an explicit `sizes` input (opset ≥ 11 — computed
    // by the host-int chains, [N, C, OH, OW]) wins over float `scales`.
    : ~ i OH 0
    : ~ i OW 0
    : ( Vec i ) sz ( __hi_vals e ( __rt_in_name n 3 ) )
    ? >= ( vec_len [i] sz ) 4 {
        = OH ?? ( vec_get [i] sz 2 ) { T v → v F _ → 0 }
        = OW ?? ( vec_get [i] sz 3 ) { T v → v F _ → 0 }
    } {
        : s sc_name ( __rt_in_name n 2 )
        = OH * H # i ( __init_f32 e sc_name 2 )
        = OW * W # i ( __init_f32 e sc_name 3 )
    }
    ( vec_free [i] sz )
    ? | <= OH 0 <= OW 0 { ( __rt_op_fail `Resize` ) ^ v } {}
    : i yd ( rt_alloc_out e ( __out_name n ) ( __shape4 1 C OH OW ) )
    : GkBuf yb @ GkBuf { yd * * C OH OW GK_F32 }
    : s mode ( node_attr_s n `mode` `nearest` )
    ? ( streq2 mode `linear` ) {
        // half-pixel bilinear (align 0) — ONNX pytorch_half_pixel and
        // half_pixel agree for every output size above 1
        ? ( gkd_resize_bilinear . e kit yb ( __rt_fbuf X ) C H W OH OW 0 ) {} { ( __rt_op_fail `Resize` ) }
    } {
        ? ( gkd_resize_nn . e kit yb ( __rt_fbuf X ) C H W OH OW / OH H / OW W ) {} { ( __rt_op_fail `Resize` ) }
    }
}

// General transpose (≤6-D): input dims + perm straight to gkd_perm (which
// pads to its 6-D kernel with trailing 1s / identity).
@ rt_transpose * Engine e ONode n → v {
    : RTensor X ( __in e n 0 )
    : i nd ( rt_ndim X )
    : ( Vec i ) dims ( vec_new [i] )
    : ( Vec i ) perm ( vec_new [i] )
    : ( Vec i ) os ( vec_new [i] )
    : ~ i k 0
    ~ < k nd {
        ( vec_push [i] dims ( rt_dim X k ) )
        ( vec_push [i] perm ( node_attr_int_at n `perm` k k ) )
        ( vec_push [i] os ( rt_dim X ( node_attr_int_at n `perm` k k ) ) )
        = k + k 1
    }
    : i yd ( rt_alloc_out e ( __out_name n ) os )
    : GkBuf yb @ GkBuf { yd . X nelem GK_F32 }
    ? ( gkd_perm . e kit yb ( __rt_fbuf X ) dims perm ) {} { ( __rt_op_fail `Transpose` ) }
    ( vec_free [i] dims )
    ( vec_free [i] perm )
}

// Softmax over `axis`, viewing the tensor as (outer, axis, inner).
@ rt_softmax * Engine e ONode n → v {
    : RTensor X ( __in e n 0 )
    // ONNX permits a negative `axis` (counts from the end). Normalise it to
    // a non-negative index before deriving outer/axis-length/inner, or the
    // softmax runs over a phantom size-1 axis (axn=1) and silently produces a
    // degenerate distribution — which poisons attention with NaN downstream.
    : ~ i ax ( node_attr_i n `axis` - ( rt_ndim X ) 1 )
    ? < ax 0 { = ax + ax ( rt_ndim X ) } {}
    : ~ i outer 1
    : ~ i j 0
    ~ < j ax { = outer * outer ( rt_dim X j ) = j + j 1 }
    : i axn ( rt_dim X ax )
    : ~ i inner 1
    : ~ i m + ax 1
    ~ < m ( rt_ndim X ) { = inner * inner ( rt_dim X m ) = m + m 1 }
    : i yd ( rt_alloc_out e ( __out_name n ) ( __shape_copy_rt . X shape ) )
    : GkBuf yb @ GkBuf { yd . X nelem GK_F32 }
    ? ( gkd_softmax_ax . e kit yb ( __rt_fbuf X ) outer axn inner ) {} { ( __rt_op_fail `Softmax` ) }
}

// Concat along `axis`, viewing each input as (outer, axis_i, inner).
@ rt_concat * Engine e ONode n → v {
    : RTensor first ( __in e n 0 )
    // negative axis counts from the end (same normalisation softmax
    // needed — torch 2.12 emits Concat axis=-1 for the level merge)
    : ~ i axis ( node_attr_i n `axis` 1 )
    ? < axis 0 { = axis + axis ( rt_ndim first ) } {}
    : ~ i outer 1
    : ~ i j 0
    ~ < j axis { = outer * outer ( rt_dim first j ) = j + j 1 }
    : ~ i inner 1
    : ~ i m + axis 1
    ~ < m ( rt_ndim first ) { = inner * inner ( rt_dim first m ) = m + m 1 }
    : i nin ( vec_len [String] . n inputs )
    : ~ i sumax 0
    : ~ i a 0
    ~ < a nin { = sumax + sumax ( rt_dim ( __in e n a ) axis ) = a + a 1 }
    // output shape = first's shape with the concat axis replaced by sumax
    : ( Vec i ) os ( vec_new [i] )
    : ~ i d 0
    ~ < d ( rt_ndim first ) { ( vec_push [i] os ? == d axis sumax ( rt_dim first d ) ) = d + d 1 }
    : i prodos ( __prod os )
    : i yd ( rt_alloc_out e ( __out_name n ) os )
    : GkBuf yb @ GkBuf { yd prodos GK_F32 }
    : ~ i off 0
    : ~ i ai 0
    ~ < ai nin {
        : RTensor src ( __in e n ai )
        : i sa ( rt_dim src axis )
        ? ( gkd_copy_ax . e kit yb ( __rt_fbuf src ) outer sa inner sumax off ) {} {
            ( __rt_op_fail `Concat` )
            ( nurl_eprint `  out=` ) ( nurl_eprint ( __out_name n ) )
            ( nurl_eprint ` in=` ) ( nurl_eprint ( __rt_in_name n ai ) )
            ( nurl_eprint ` nelem=` ) ( nurl_eprint ( nurl_str_int . src nelem ) )
            ( nurl_eprint ` want outer*sa*inner=` )
            ( nurl_eprint ( nurl_str_int * * outer sa inner ) )
            ( nurl_eprint `\n` )
        }
        = off + off sa
        = ai + ai 1
    }
}

// Split along `axis` into contiguous slices — alias each output onto the
// input buffer at its byte offset (no copy). Sizes from the INT64 init
// input[1] when present, else `num_outputs` equal parts.
@ rt_split * Engine e ONode n → v {
    : RTensor X ( __in e n 0 )
    : i axis ( node_attr_i n `axis` 1 )
    : ~ i outer 1
    : ~ i j 0
    ~ < j axis { = outer * outer ( rt_dim X j ) = j + j 1 }
    : ~ i inner 1
    : ~ i m + axis 1
    ~ < m ( rt_ndim X ) { = inner * inner ( rt_dim X m ) = m + m 1 }
    : i nout ( vec_len [String] . n outputs )
    : ~ b have_sizes F
    : ~ s sz_name ``
    ? > ( vec_len [String] . n inputs ) 1 {
        = sz_name ( string_data ?? ( vec_get [String] . n inputs 1 ) { T x → x F _ → ( string_new ) } )
        ? > ( __init_i64_len e sz_name ) 0 { = have_sizes T } {}
    } {}
    : i src_ax ( rt_dim X axis )
    : i eq / src_ax nout
    : ~ i off 0
    : ~ i k 0
    ~ < k nout {
        : i sz ? have_sizes ( __init_i64 e sz_name k ) eq
        : ( Vec i ) os ( vec_new [i] )
        : ~ i d 0
        ~ < d ( rt_ndim X ) { ( vec_push [i] os ? == d axis sz ( rt_dim X d ) ) = d + d 1 }
        : s onm ( string_data ?? ( vec_get [String] . n outputs k ) { T x → x F _ → ( string_new ) } )
        ? == outer 1 {
            // contiguous slice — alias the input buffer at the byte offset
            ( rt_put e onm + . X dptr * * off inner 4 os )
        } {
            // interleaved slice (outer>1) — must copy into a fresh buffer
            : i prodos ( __prod os )
            : i od ( rt_alloc_out e onm os )
            : GkBuf ob @ GkBuf { od prodos GK_F32 }
            ? ( gkd_slice_ax . e kit ob ( __rt_fbuf X ) outer sz inner src_ax off ) {} { ( __rt_op_fail `Split` ) }
        }
        = off + off sz
        = k + k 1
    }
}

// MatMul. Two cases: A[...,M,K] @ B[K,N] (2-D B) collapses leading dims
// into M and uses Gemm; A[...,M,K] @ B[...,K,N] (matching batch dims, the
// attention case) uses a batched matmul.
@ rt_matmul * Engine e ONode n → v {
    : RTensor A ( __in e n 0 )
    : RTensor B ( __in e n 1 )
    : i Kd ( rt_last A )
    : i N ( rt_last B )
    ? > ( rt_ndim B ) 2 {
        // batched: A[batch,M,K] @ B[batch,K,N] -> [batch,M,N]
        : i M ( rt_dim A - ( rt_ndim A ) 2 )
        : i batch / . A nelem * M Kd
        : ( Vec i ) os ( vec_new [i] )
        : ~ i d 0
        ~ < d - ( rt_ndim A ) 1 { ( vec_push [i] os ( rt_dim A d ) ) = d + d 1 }
        ( vec_push [i] os N )
        : i yd ( rt_alloc_out e ( __out_name n ) os )
        : GkBuf yb @ GkBuf { yd * * batch M N GK_F32 }
        ? ( gkd_bmm . e kit yb ( __rt_fbuf A ) ( __rt_fbuf B ) batch M Kd N 1 1 ) {} { ( __rt_op_fail `MatMul` ) }
    } {
        : i M / . A nelem Kd
        : ( Vec i ) os ( vec_new [i] )
        : ~ i d 0
        ~ < d - ( rt_ndim A ) 1 { ( vec_push [i] os ( rt_dim A d ) ) = d + d 1 }
        ( vec_push [i] os N )
        : i yd ( rt_alloc_out e ( __out_name n ) os )
        : GkBuf yb @ GkBuf { yd * M N GK_F32 }
        ? ( gkd_gemm . e kit yb ( __rt_fbuf A ) ( __rt_fbuf B ) ( __rt_fbuf A ) 0 M N Kd 1.0 0.0 0 ) {} { ( __rt_op_fail `MatMul` ) }
    }
}

// LayerNormalization over the last axis (scale = in1, bias = in2).
@ rt_layernorm * Engine e ONode n → v {
    : RTensor X ( __in e n 0 )
    : RTensor sc ( __in e n 1 )
    : RTensor bi ( __in e n 2 )
    : i ax ( rt_last X )
    : i outer / . X nelem ax
    : f eps ( node_attr_f n `epsilon` 0.00001 )
    : i yd ( rt_alloc_out e ( __out_name n ) ( __shape_copy_rt . X shape ) )
    : GkBuf yb @ GkBuf { yd . X nelem GK_F32 }
    ? ( gkd_layernorm . e kit yb ( __rt_fbuf X ) ( __rt_fbuf sc ) ( __rt_fbuf bi ) outer ax eps ) {} { ( __rt_op_fail `LayerNormalization` ) }
}

@ rt_erf * Engine e ONode n → v {
    : RTensor X ( __in e n 0 )
    : i yd ( rt_alloc_out e ( __out_name n ) ( __shape_copy_rt . X shape ) )
    : GkBuf yb @ GkBuf { yd . X nelem GK_F32 }
    ? ( gkd_erf . e kit yb ( __rt_fbuf X ) ) {} { ( __rt_op_fail `Erf` ) }
}

// GatherND — specialised for the CLIP EOS read-out: data [B,L,D] and an
// index built from (arange, argmax(tokens)) selecting each row's EOS token.
// Rather than materialise the int64 index chain, gather directly from the
// graph's token input: out[b,:] = data[b, argmax(tokens[b]), :].
@ rt_gathernd * Engine e ONode n → v {
    : RTensor data ( __in e n 0 )
    : i B ( rt_dim data 0 )
    : i L ( rt_dim data 1 )
    : i D ( rt_dim data 2 )
    : OGraph gr . e graph
    : RTensor tok ( rt_at e ( rt_find e ( string_data . gr input_name ) ) )
    : i yd ( rt_alloc_out e ( __out_name n ) ( __shape2 B D ) )
    : GkBuf yb @ GkBuf { yd * B D GK_F32 }
    ? ( gkd_eos_gather . e kit yb ( __rt_fbuf data ) ( __rt_ibuf tok ) B L D ) {} { ( __rt_op_fail `GatherND` ) }
}

// Gather along `axis`. Two index sources: a device tensor (e.g. the token
// matrix → embedding lookup) gathers nidx rows; a host scalar initializer
// (e.g. the QKV split index) selects one slice and drops the axis.
// ArgMax along the last axis. The output is int64 (allocated at 8
// bytes/elem — rt_alloc_out's 4-byte default would let the kernel write
// past the buffer). Dispatches to the int64 kernel when the input is the
// graph's raw token input (the only 8-byte tensor in play; everything
// else on the value map is f32). Used by the CLIP text encoder's EOT
// read-out (ArgMax over token ids → Gather), which onnxsim leaves as a
// plain ArgMax+Gather pair — the eos_gather fast path only matches the
// old GatherND formulation.
@ rt_argmax * Engine e ONode n → v {
    : RTensor x ( __in e n 0 )
    : i nd0 ( rt_ndim x )
    : ~ i axis ( node_attr_i n `axis` 0 )
    ? < axis 0 { = axis + axis nd0 } {}
    ? != axis - nd0 1 { ( nurl_eprint `[onnx] ArgMax: only last-axis supported\n` ) } {
        : i ax ( rt_dim x axis )
        : ~ i outer 1
        : ~ i j 0
        ~ < j axis { = outer * outer ( rt_dim x j ) = j + j 1 }
        : i keep ( node_attr_i n `keepdims` 1 )
        : ( Vec i ) os ( vec_new [i] )
        : ~ i d 0
        ~ < d axis { ( vec_push [i] os ( rt_dim x d ) ) = d + d 1 }
        ? != keep 0 { ( vec_push [i] os 1 ) } {}
        : i prodos ( __prod os )
        : GpuBuffer buf ( gpu_alloc . e g * prodos 8 )
        ( rt_own e . buf dptr )
        ( rt_put e ( __out_name n ) . buf dptr os )
        : GkBuf ob @ GkBuf { . buf dptr prodos GK_I64 }
        : s in0 ( string_data ?? ( vec_get [String] . n inputs 0 ) { T x2 → x2 F _ → ( string_new ) } )
        // gkd_argmax picks its kernel by the INPUT buffer's element type;
        // the raw token input is the only int64 tensor in play.
        : GkBuf xb ? ( streq2 in0 ( string_data . . e graph input_name ) ) { ( __rt_ibuf x ) } { ( __rt_fbuf x ) }
        ? ( gkd_argmax . e kit ob xb outer ax ) {} { ( __rt_op_fail `ArgMax` ) }
    }
}

@ rt_gather * Engine e ONode n → v {
    : RTensor data ( __in e n 0 )
    : ~ i axis ( node_attr_i n `axis` 0 )
    ? < axis 0 { = axis + axis ( rt_ndim data ) } {}
    : i axis_in ( rt_dim data axis )
    : ~ i outer 1
    : ~ i j 0
    ~ < j axis { = outer * outer ( rt_dim data j ) = j + j 1 }
    : ~ i inner 1
    : ~ i m + axis 1
    ~ < m ( rt_ndim data ) { = inner * inner ( rt_dim data m ) = m + m 1 }
    : s idx_name ( string_data ?? ( vec_get [String] . n inputs 1 ) { T x → x F _ → ( string_new ) } )
    : i idx_in_map ( rt_find e idx_name )
    ? >= idx_in_map 0 {
        // device int64 indices → out shape = data[:axis] ++ idx.shape ++ data[axis+1:]
        : RTensor idxt ( rt_at e idx_in_map )
        : i nidx . idxt nelem
        : ( Vec i ) os ( vec_new [i] )
        : ~ i d 0
        ~ < d axis { ( vec_push [i] os ( rt_dim data d ) ) = d + d 1 }
        : ~ i q 0
        ~ < q ( rt_ndim idxt ) { ( vec_push [i] os ( rt_dim idxt q ) ) = q + q 1 }
        : ~ i r + axis 1
        ~ < r ( rt_ndim data ) { ( vec_push [i] os ( rt_dim data r ) ) = r + r 1 }
        : i prodos ( __prod os )
        : i yd ( rt_alloc_out e ( __out_name n ) os )
        : GkBuf yb @ GkBuf { yd prodos GK_F32 }
        : GkBuf ixb @ GkBuf { . idxt dptr nidx GK_I64 }
        ? ( gkd_gather . e kit yb ( __rt_fbuf data ) ixb outer axis_in inner nidx ) {} { ( __rt_op_fail `Gather` ) }
    } {
        // host scalar index → slice one element along axis (axis removed);
        // a negative index wraps once (ONNX)
        : ~ i s ( __init_i64 e idx_name 0 )
        ? < s 0 { = s + s axis_in } {}
        : ( Vec i ) os ( vec_new [i] )
        : ~ i d 0
        ~ < d ( rt_ndim data ) { ? != d axis { ( vec_push [i] os ( rt_dim data d ) ) } {} = d + d 1 }
        : i prodos ( __prod os )
        : i yd ( rt_alloc_out e ( __out_name n ) os )
        : GkBuf yb @ GkBuf { yd prodos GK_F32 }
        ? ( gkd_slice_ax . e kit yb ( __rt_fbuf data ) outer 1 inner axis_in s ) {} { ( __rt_op_fail `Gather` ) }
    }
}

// Einsum "bchw,bkc->bkhw": region[1,C,H,W] · text[1,K,C] -> [1,K,H,W].
// = Gemm(text[K,C], region[C,HW]) -> [K,HW].
@ rt_einsum * Engine e ONode n → v {
    : s eq ( node_attr_s n `equation` `` )
    : RTensor region ( __in e n 0 )
    : RTensor text ( __in e n 1 )
    : i C ( rt_dim region 1 )
    : i H ( rt_dim region 2 )
    : i Wd ( rt_dim region 3 )
    : i HW * H Wd
    : i Kk ( rt_dim text 1 )
    : i yd ( rt_alloc_out e ( __out_name n ) ( __shape4 1 Kk H Wd ) )
    : GkBuf yb @ GkBuf { yd * Kk HW GK_F32 }
    ? ( gkd_gemm . e kit yb ( __rt_fbuf text ) ( __rt_fbuf region ) ( __rt_fbuf text ) 0 Kk HW C 1.0 0.0 0 ) {} { ( __rt_op_fail `Einsum` ) }
}

@ rt_reducel2 * Engine e ONode n → v {
    : RTensor X ( __in e n 0 )
    : i ax ( rt_last X )
    : i outer / . X nelem ax
    : ( Vec i ) os ( vec_new [i] )
    : ~ i d 0
    ~ < d - ( rt_ndim X ) 1 { ( vec_push [i] os ( rt_dim X d ) ) = d + d 1 }
    ( vec_push [i] os 1 )
    : i yd ( rt_alloc_out e ( __out_name n ) os )
    : GkBuf yb @ GkBuf { yd outer GK_F32 }
    ? ( gkd_reducel2 . e kit yb ( __rt_fbuf X ) outer ax ) {} { ( __rt_op_fail `ReduceL2` ) }
}

@ rt_clip * Engine e ONode n → v {
    : RTensor X ( __in e n 0 )
    : ~ f lo - 0.0 1000000000.0
    : ~ f hi 1000000000.0
    // min/max are OPTIONAL inputs — an omitted one arrives as an empty
    // name ("" placeholder input), which must keep the default, not
    // read a nonexistent initializer as 0.0 (that clamped everything).
    ? > ( vec_len [String] . n inputs ) 1 {
        : s lon ( string_data ?? ( vec_get [String] . n inputs 1 ) { T x → x F _ → ( string_new ) } )
        ? > ( nurl_str_len lon ) 0 { = lo ( __init_f32 e lon 0 ) } {}
    } {}
    ? > ( vec_len [String] . n inputs ) 2 {
        : s hin ( string_data ?? ( vec_get [String] . n inputs 2 ) { T x → x F _ → ( string_new ) } )
        ? > ( nurl_str_len hin ) 0 { = hi ( __init_f32 e hin 0 ) } {}
    } {}
    : i yd ( rt_alloc_out e ( __out_name n ) ( __shape_copy_rt . X shape ) )
    : GkBuf yb @ GkBuf { yd . X nelem GK_F32 }
    ? ( gkd_clip . e kit yb ( __rt_fbuf X ) lo hi ) {} { ( __rt_op_fail `Clip` ) }
}

// Expand the last axis (broadcast a (...,1) tensor to the target shape).
@ rt_expand * Engine e ONode n → v {
    : RTensor X ( __in e n 0 )
    : s shp_name ( string_data ?? ( vec_get [String] . n inputs 1 ) { T x → x F _ → ( string_new ) } )
    : i nd ( __init_i64_len e shp_name )
    : i rep ( __init_i64 e shp_name - nd 1 )
    : i outer . X nelem
    : ( Vec i ) os ( vec_new [i] )
    : ~ i d 0
    ~ < d nd { ( vec_push [i] os ( __init_i64 e shp_name d ) ) = d + d 1 }
    : i prodos ( __prod os )
    : i yd ( rt_alloc_out e ( __out_name n ) os )
    : GkBuf yb @ GkBuf { yd prodos GK_F32 }
    ? ( gkd_expandlast . e kit yb ( __rt_fbuf X ) outer rep ) {} { ( __rt_op_fail `Expand` ) }
}

// Unsqueeze: insert size-1 axes — pure reshape (alias). New shape from the
// input's shape with 1s inserted at the `axes` positions.
@ rt_unsqueeze * Engine e ONode n → v {
    : RTensor X ( __in e n 0 )
    : s ax_name ( string_data ?? ( vec_get [String] . n inputs 1 ) { T x → x F _ → ( string_new ) } )
    : i a0 ( __init_i64 e ax_name 0 )
    : ( Vec i ) os ( vec_new [i] )
    : i nd ( rt_ndim X )
    : ~ i d 0
    ~ <= d nd {
        ? == d a0 { ( vec_push [i] os 1 ) } {}
        ? < d nd { ( vec_push [i] os ( rt_dim X d ) ) } {}
        = d + d 1
    }
    ( rt_put e ( __out_name n ) . X dptr os )
}

// Run the graph on a host input buffer (raw f32). `shape` is the input
// tensor shape (e.g. [1,3,416,416]). Returns the output device tensor.
@ rt_run_shaped * Engine e OGraph g * u input_host ( Vec i ) shape → RTensor {
    ( rt_reset e )
    ( _rt_set_graph e g )
    ( rt_load_inits e g )
    : i n ( __prod shape )
    : GpuBuffer ib ( gpu_alloc . e g * n 4 )
    ( rt_own e . ib dptr )
    ( gpu_upload ib input_host )
    ( rt_put e ( string_data . g input_name ) . ib dptr shape )
    ^ ( _rt_run_nodes e g )
}

// Token run: the single input is an INT64 token matrix [nrow, ncol] already
// laid out in `tokhost` (8-byte LE). Uploaded as-is for the embedding Gather.
@ rt_run_tokens * Engine e OGraph g * u tokhost i nrow i ncol → RTensor {
    ( rt_reset e )
    ( _rt_set_graph e g )
    ( rt_load_inits e g )
    : GpuBuffer ib ( gpu_alloc . e g * * nrow ncol 8 )
    ( rt_own e . ib dptr )
    ( gpu_upload ib tokhost )
    ( rt_put e ( string_data . g input_name ) . ib dptr ( __shape2 nrow ncol ) )
    ^ ( _rt_run_nodes e g )
}

// Two-input run (e.g. image + text embeddings for a promptable model).
@ rt_run_two * Engine e OGraph g s n1 * u h1 ( Vec i ) s1 s n2 * u h2 ( Vec i ) s2 → RTensor {
    ( rt_reset e )
    ( _rt_set_graph e g )
    ( rt_load_inits e g )
    : GpuBuffer b1 ( gpu_alloc . e g * ( __prod s1 ) 4 )
    ( rt_own e . b1 dptr )
    ( gpu_upload b1 h1 ) ( rt_put e n1 . b1 dptr s1 )
    : GpuBuffer b2 ( gpu_alloc . e g * ( __prod s2 ) 4 )
    ( rt_own e . b2 dptr )
    ( gpu_upload b2 h2 ) ( rt_put e n2 . b2 dptr s2 )
    ^ ( _rt_run_nodes e g )
}

@ _rt_run_nodes * Engine e OGraph g → RTensor {
    // Chain every launch on the stream; one device sync at the end (the
    // CUDA stream serialises kernels, the CPU backend is synchronous).
    ( gk_autosync F )
    : ( Vec ONode ) nodes . g nodes
    : ~ i k 0
    ~ < k ( vec_len [ONode] nodes ) {
        ?? ( vec_get [ONode] nodes k ) {
            T nd → {
                : s op ( string_data . nd op_type )
                // Skip a node whose first input was never produced (e.g. the
                // segmentation branch hanging off the unsupported ConvTranspose):
                // running an op on an empty (dptr 0) tensor would do an illegal
                // device read and corrupt the whole CUDA context. Detection
                // (output0) doesn't depend on that branch.
                : s in0 ( string_data ?? ( vec_get [String] . nd inputs 0 ) { T x → x F _ → ( string_new ) } )
                : b ready | == ( vec_len [String] . nd inputs ) 0 >= ( rt_find e in0 ) 0
                // Shape arithmetic first: Constant / Shape and any int
                // chain op whose data is host-side never touch the device.
                ? ( __rt_host_step e nd ) {} {
                    ? ! ready {} {
                        ? ( streq2 op `Gemm` ) { ( rt_gemm e nd ) }
                        ? ( streq2 op `Relu` ) { ( rt_relu e nd ) }
                        ? ( streq2 op `Conv` ) { ( rt_conv e nd ) }
                        ? ( streq2 op `ConvTranspose` ) { ( rt_convtranspose e nd ) }
                        ? ( streq2 op `MaxPool` ) { ( rt_maxpool e nd ) }
                        ? ( streq2 op `BatchNormalization` ) { ( rt_batchnorm e nd ) }
                        ? ( streq2 op `LeakyRelu` ) { ( rt_leakyrelu e nd ) }
                        ? ( streq2 op `Mul` ) { ( rt_binop e nd 0 ) }
                        ? ( streq2 op `Add` ) { ( rt_binop e nd 1 ) }
                        ? ( streq2 op `Sub` ) { ( rt_binop e nd 2 ) }
                        ? ( streq2 op `Div` ) { ( rt_binop e nd 3 ) }
                        ? ( streq2 op `Sigmoid` ) { ( rt_sigmoid e nd ) }
                        ? ( streq2 op `Concat` ) { ( rt_concat e nd ) }
                        ? ( streq2 op `Split` ) { ( rt_split e nd ) }
                        ? ( streq2 op `Slice` ) { ( rt_slice e nd ) }
                        ? ( streq2 op `Reshape` ) { ( rt_reshape e nd ) }
                        ? ( streq2 op `Resize` ) { ( rt_resize e nd ) }
                        ? ( streq2 op `Transpose` ) { ( rt_transpose e nd ) }
                        ? ( streq2 op `Softmax` ) { ( rt_softmax e nd ) }
                        ? ( streq2 op `MatMul` ) { ( rt_matmul e nd ) }
                        ? ( streq2 op `Einsum` ) { ( rt_einsum e nd ) }
                        ? ( streq2 op `ReduceL2` ) { ( rt_reducel2 e nd ) }
                        ? ( streq2 op `Clip` ) { ( rt_clip e nd ) }
                        ? ( streq2 op `Expand` ) { ( rt_expand e nd ) }
                        ? ( streq2 op `Unsqueeze` ) { ( rt_unsqueeze e nd ) }
                        ? ( streq2 op `LayerNormalization` ) { ( rt_layernorm e nd ) }
                        ? ( streq2 op `Erf` ) { ( rt_erf e nd ) }
                        ? ( streq2 op `Gather` ) { ( rt_gather e nd ) }
                        ? ( streq2 op `GatherND` ) { ( rt_gathernd e nd ) }
                        ? ( streq2 op `ArgMax` ) { ( rt_argmax e nd ) }
                        ? ( streq2 op `Shape` ) {}
                        ? ( streq2 op `Range` ) {}
                        ? ( streq2 op `Squeeze` ) {}
                        { ( nurl_eprint `[onnx] unsupported op: ` ) ( nurl_eprint op ) ( nurl_eprint `\n` ) }
                    }
                }
            } F _ → {}
        }
        = k + k 1
    }
    ( gk_autosync T )
    ( gpu_sync . e g )
    : i oi ( rt_find e ( string_data . g output_name ) )
    ^ ( rt_at e oi )
}

// Convenience for a 2-D (dense) input.
@ rt_run * Engine e OGraph g * u input_host i in_rows i in_cols → RTensor {
    ^ ( rt_run_shaped e g input_host ( __shape2 in_rows in_cols ) )
}

// Download a device tensor into a fresh host f32 buffer (caller frees).
@ rt_download * Engine e RTensor t → *u {
    : i n . t nelem
    : *u host ( gpu_host_alloc * n 4 )
    : GpuBuffer b @ GpuBuffer { . t dptr * n 4 }
    ( gpu_download host b )
    ^ host
}

// The model's SECOND output (segmentation proto) after a run — valid until
// the next rt_reset. nelem 0 if the model has no second output. The value
// map still holds it because reset only happens at the start of a run.
@ rt_output1 * Engine e → RTensor {
    : s nm ( string_data . . e graph output1_name )
    ? == ( nurl_str_len nm ) 0 { ^ @ RTensor { ( string_new ) 0 ( vec_new [i] ) 0 } } {}
    : i oi ( rt_find e nm )
    ? < oi 0 { ^ @ RTensor { ( string_new ) 0 ( vec_new [i] ) 0 } } { ^ ( rt_at e oi ) }
}

@ rt_close * Engine e → v {
    ( rt_reset e )
    ( vec_free [i] . e owned )
    ( vec_free [RTensor] . e vals )
    ( gk_close . e kit )  // releases the device Engine.g borrows
    ( nurl_free # *u e )
}

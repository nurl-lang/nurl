// grad/opt.nu — optimizers over tape parameters: SGD and Adam, per-parameter
// L2 (weight decay), optional global-norm gradient clipping.
//
// An optimizer is built empty (`opt_adam_new lr` / `opt_sgd_new lr`) and
// parameters are added one by one with their OWN L2 coefficient
// (`opt_add o tp p alpha`) — weights typically carry alpha, biases 0, which
// is the param-groups need in miniature. `opt_step o tp` reads each
// parameter's accumulated gradient from the tape and updates the parameter
// value IN PLACE on the tape (the tape owns the live copy; read it back with
// gvar_value).
//
// Semantics:
//   g       = grad + alpha·w          (L2 applied to the raw gradient; the
//                                      loss is expected to be mean-scaled —
//                                      no hidden batch divide here)
//   SGD     : w -= lr·g
//   Adam    : m = β1·m + (1−β1)·g ; v = β2·v + (1−β2)·g²
//             w -= lr·√(1−β2ᵗ)/(1−β1ᵗ) · m/(√v + ε)
//             β1 = 0.9, β2 = 0.999, ε = 1e-8 — sklearn/PyTorch defaults.
//
// The step counter lives behind the *Opt heap pointer, so it ADVANCES — the
// frozen-Adam-t bug class (a scalar counter field on a by-value struct never
// persists in NURL) cannot recur, and tests/opt pin the trajectory bit-for-
// bit against a hand-computed two-step Adam.
//
// Clipping (`opt_set_clip o maxn`): one global L2 norm over every added
// parameter's gradient; if it exceeds maxn every gradient is scaled by
// maxn/norm before the update — the standard clip-by-global-norm.
//
// A parameter whose gradient was never touched by backward() is SKIPPED
// (PyTorch's None-grad rule), not decayed.

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `src/grad.nu`
$ `deps/tensor/src/tensor.nu`

: Opt {
    i kind  // 0 sgd · 1 adam
    f lr
    f clip  // 0 = off
    i t  // Adam step count (advances — behind the heap pointer)
    i total  // total moment elements
    ( Vec i ) ids  // param node ids
    ( Vec f ) alphas  // per-param L2
    ( Vec i ) offs  // each param's slab offset into m / v
    ( Vec i ) lens  // each param's element count
    ( Vec f ) m  // first moments (adam)
    ( Vec f ) v  // second moments (adam)
}

@ _opt_new i kind f lr → *Opt {
    : *Opt o # *Opt ( nurl_alloc Z Opt )
    = . o kind kind
    = . o lr lr
    = . o clip 0.0
    = . o t 0
    = . o total 0
    = . o ids ( vec_new [i] )
    = . o alphas ( vec_new [f] )
    = . o offs ( vec_new [i] )
    = . o lens ( vec_new [i] )
    = . o m ( vec_new [f] )
    = . o v ( vec_new [f] )
    ^ o
}

@ opt_sgd_new f lr → *Opt { ^ ( _opt_new 0 lr ) }

@ opt_adam_new f lr → *Opt { ^ ( _opt_new 1 lr ) }

@ opt_free * Opt o → v {
    ( vec_free [i] . o ids )
    ( vec_free [f] . o alphas )
    ( vec_free [i] . o offs )
    ( vec_free [i] . o lens )
    ( vec_free [f] . o m )
    ( vec_free [f] . o v )
    ( nurl_free # s o )
}

@ opt_set_clip * Opt o f maxn → v { = . o clip maxn }

// Register one tape parameter with its L2 coefficient (0 for biases).
@ opt_add * Opt o * GTape tp GVar p f alpha → v {
    ? >= . p id 0 {} { ^ v }
    : *Tensor w # *Tensor ( _g_val tp . p id )
    : i n ( vec_len [f] . w data )
    ( vec_push [i] . o ids . p id )
    ( vec_push [f] . o alphas alpha )
    ( vec_push [i] . o offs . o total )
    ( vec_push [i] . o lens n )
    : ~ i k 0
    ~ < k n {
        ( vec_push [f] . o m 0.0 )
        ( vec_push [f] . o v 0.0 )
        = k + k 1
    }
    = . o total + . o total n
}

// The global L2 norm of every registered parameter's gradient (0-grads skip).
@ _opt_gnorm * Opt o * GTape tp → f {
    : ~ f ss 0.0
    : i np ( vec_len [i] . o ids )
    : ~ i pi 0
    ~ < pi np {
        : i id ( _ti . o ids pi )
        : s gp ( _g_grad_ptr tp id )
        ? != # i gp 0 {
            : *Tensor g # *Tensor gp
            : i n ( vec_len [f] . g data )
            : ~ i k 0
            ~ < k n {
                : f gk ( _tf . g data k )
                = ss + ss * gk gk
                = k + k 1
            }
        } {}
        = pi + pi 1
    }
    ^ ( float_sqrt ss )
}

// One update step from the gradients currently on the tape.
@ opt_step * Opt o * GTape tp → v {
    // global-norm clip factor (1.0 = no scaling)
    : ~ f cs 1.0
    ? > . o clip 0.0 {
        : f gn ( _opt_gnorm o tp )
        ? > gn . o clip { = cs / . o clip gn } {}
    } {}
    : ~ f lrt . o lr
    ? == . o kind 1 {
        = . o t + . o t 1
        : f tf # f . o t
        = lrt * . o lr / ( float_sqrt - 1.0 ( pow 0.999 tf ) ) - 1.0 ( pow 0.9 tf )
    } {}
    : i np ( vec_len [i] . o ids )
    : ~ i pi 0
    ~ < pi np {
        : i id ( _ti . o ids pi )
        : s gp ( _g_grad_ptr tp id )
        ? != # i gp 0 {
            : *Tensor g # *Tensor gp
            : *Tensor w # *Tensor ( _g_val tp id )
            : f alpha ( _tf . o alphas pi )
            : i off ( _ti . o offs pi )
            : i n ( _ti . o lens pi )
            : ~ i k 0
            ~ < k n {
                : f gk + * ( _tf . g data k ) cs * alpha ( _tf . w data k )
                ? == . o kind 0 {
                    ( vec_set [f] . w data k - ( _tf . w data k ) * . o lr gk )
                } {
                    : i mk + off k
                    // (1−β) computed at runtime — the same arithmetic mlp's
                    // Adam and the aegpu kernels use, so every Adam in the
                    // ecosystem shares one trajectory formula.
                    : f nm + * 0.9 ( _tf . o m mk ) * - 1.0 0.9 gk
                    : f nv + * 0.999 ( _tf . o v mk ) * - 1.0 0.999 * gk gk
                    ( vec_set [f] . o m mk nm )
                    ( vec_set [f] . o v mk nv )
                    ( vec_set [f] . w data k - ( _tf . w data k ) / * lrt nm + ( float_sqrt nv ) 0.00000001 )
                }
                = k + k 1
            }
        } {}
        = pi + pi 1
    }
}

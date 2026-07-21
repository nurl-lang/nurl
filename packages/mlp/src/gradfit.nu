// mlp/gradfit.nu — the sklearn recipe over the `grad` autograd engine.
//
// mlp_train_grad / mlp_fit_grad run the SAME recipe as mlp_train / mlp_fit —
// the same seeded PRNG call order (Glorot init, the one full shuffle, the
// per-epoch train-region shuffles), the same validation split, minibatch
// bounds, early-stopping/patience/best-weights logic and restart selection —
// but the forward pass, the backward pass and Adam come from `grad`: the
// backward is DERIVED from the graph, not hand-written.
//
// The per-batch loss reproduces the hand path's gradient exactly in form:
//
//     L = (Σ e²  +  α · Σ‖W‖²) / (2·B)
//     ⇒ dL/dW = (Σ δ·a + α·W) / B   — precisely mlp_train's Adam input
//                                     (sklearn's _backprop, L2 on weights
//                                     only, batch divide after).
//
// Results are recipe-equal, not bit-equal, to the hand path (batched matmuls
// accumulate in a different order than per-row loops); the sklearn oracle
// passes against BOTH engines. The hand path stays the default until grad's
// GPU backward (M5) can replace anomaly's aegpu mirror wholesale — then the
// duplication goes, with no window where any downstream guarantee breaks.
//
// The trained model lands back in the ordinary Mlp struct (weights
// transposed between mlp's [fout,fin] rows and the tape's [fin,fout]
// matmul layout), so mlp_predict / mlp_save / mlp_load work unchanged.
// Adam moments stay in the optimizer; the model's mw/vw/mb/vb remain zero
// (mlp_save never persisted them).

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/rng.nu`
$ `mlp.nu`
$ `deps/grad/src/grad.nu`
$ `deps/grad/src/opt.nu`
$ `deps/tensor/src/tensor.nu`

// Layer l's weights as a tape parameter in matmul layout: tape[i*fout+j] =
// m.w[wo + j*fin + i] (mlp stores [fout,fin] rows).
@ _gf_wparam * GTape tp Mlp m i l → GVar {
    : i fin ( _mlp_iget . m sizes l )
    : i fout ( _mlp_iget . m sizes + l 1 )
    : i wo ( _mlp_iget . m w_off l )
    : ( Vec f ) wt ( vec_with_cap [f] * fin fout )
    : ~ i i2 0
    ~ < i2 fin {
        : ~ i j 0
        ~ < j fout {
            ( vec_push [f] wt ( _mlp_fget . m w + wo + * j fin i2 ) )
            = j + j 1
        }
        = i2 + i2 1
    }
    : ( Vec i ) shp ( vec_new [i] )
    ( vec_push [i] shp fin ) ( vec_push [i] shp fout )
    : Tensor t ( tensor_of TE_F64 shp wt )
    : GVar p ( grad_param tp t )
    ( tensor_free t )
    ^ p
}

@ _gf_bparam * GTape tp Mlp m i l → GVar {
    : i fout ( _mlp_iget . m sizes + l 1 )
    : i bo ( _mlp_iget . m b_off l )
    : ( Vec f ) bv ( vec_with_cap [f] fout )
    : ~ i j 0
    ~ < j fout { ( vec_push [f] bv ( _mlp_fget . m b + bo j ) ) = j + j 1 }
    : ( Vec i ) shp ( vec_new [i] )
    ( vec_push [i] shp fout )
    : Tensor t ( tensor_of TE_F64 shp bv )
    : GVar p ( grad_param tp t )
    ( tensor_free t )
    ^ p
}

// Rows idx[from..to) of the row-major table `X` (n×d) as a [count,d] const.
@ _gf_rows_const * GTape tp ( Vec f ) X i d ( Vec i ) idx i from i to → GVar {
    : i cnt - to from
    : ( Vec f ) buf ( vec_with_cap [f] * cnt d )
    : ~ i k from
    ~ < k to {
        : i r ( _mlp_iget idx k )
        : ~ i c 0
        ~ < c d { ( vec_push [f] buf ( _mlp_fget X + * r d c ) ) = c + c 1 }
        = k + k 1
    }
    : ( Vec i ) shp ( vec_new [i] )
    ( vec_push [i] shp cnt ) ( vec_push [i] shp d )
    : Tensor t ( tensor_of TE_F64 shp buf )
    : GVar v ( grad_const tp t )
    ( tensor_free t )
    ^ v
}

// The network forward on the tape: relu hidden layers, linear output.
@ _gf_forward * GTape tp GVar xb ( Vec GVar ) ws ( Vec GVar ) bs i nl → GVar {
    : ~ GVar h xb
    : ~ i l 0
    ~ < l nl {
        : GVar wl ?? ( vec_get [GVar] ws l ) { T x → x F → @ GVar { -1 } }
        : GVar bl ?? ( vec_get [GVar] bs l ) { T x → x F → @ GVar { -1 } }
        : GVar z ( g_add tp ( g_matmul tp h wl ) bl )
        ? < l - nl 1 { = h ( g_relu tp z ) } { = h z }
        = l + l 1
    }
    ^ h
}

// Copy the (tape-layout) trained values back into the Mlp struct.
@ _gf_write_back Mlp m * GTape tp ( Vec GVar ) ws ( Vec GVar ) bs i nl → v {
    : ~ i l 0
    ~ < l nl {
        : i fin ( _mlp_iget . m sizes l )
        : i fout ( _mlp_iget . m sizes + l 1 )
        : i wo ( _mlp_iget . m w_off l )
        : i bo ( _mlp_iget . m b_off l )
        : GVar wl ?? ( vec_get [GVar] ws l ) { T x → x F → @ GVar { -1 } }
        : GVar bl ?? ( vec_get [GVar] bs l ) { T x → x F → @ GVar { -1 } }
        : Tensor wv ( gvar_value tp wl )
        : Tensor bv ( gvar_value tp bl )
        : ~ i i2 0
        ~ < i2 fin {
            : ~ i j 0
            ~ < j fout {
                ( vec_set [f] . m w + wo + * j fin i2 ( _tf . wv data + * i2 fout j ) )
                = j + j 1
            }
            = i2 + i2 1
        }
        : ~ i j2 0
        ~ < j2 fout { ( vec_set [f] . m b + bo j2 ( _tf . bv data j2 ) ) = j2 + j2 1 }
        = l + l 1
    }
}

// Snapshot every parameter's current tape value into one flat buffer
// (tape layout, params in ws-then-bs order) — the best-weights store.
@ _gf_snapshot * GTape tp ( Vec GVar ) ws ( Vec GVar ) bs i nl ( Vec f ) dst → v {
    ( vec_clear [f] dst )
    : ~ i l 0
    ~ < l nl {
        : GVar wl ?? ( vec_get [GVar] ws l ) { T x → x F → @ GVar { -1 } }
        : Tensor wv ( gvar_value tp wl )
        : i n ( vec_len [f] . wv data )
        : ~ i k 0
        ~ < k n { ( vec_push [f] dst ( _tf . wv data k ) ) = k + k 1 }
        = l + l 1
    }
    = l 0
    ~ < l nl {
        : GVar bl ?? ( vec_get [GVar] bs l ) { T x → x F → @ GVar { -1 } }
        : Tensor bv ( gvar_value tp bl )
        : i n ( vec_len [f] . bv data )
        : ~ i k 0
        ~ < k n { ( vec_push [f] dst ( _tf . bv data k ) ) = k + k 1 }
        = l + l 1
    }
}

// Restore a snapshot into the live tape parameters.
@ _gf_restore * GTape tp ( Vec GVar ) ws ( Vec GVar ) bs i nl ( Vec f ) src → v {
    : ~ i off 0
    : ~ i l 0
    ~ < l nl {
        : GVar wl ?? ( vec_get [GVar] ws l ) { T x → x F → @ GVar { -1 } }
        : Tensor wv ( gvar_value tp wl )
        : i n ( vec_len [f] . wv data )
        : ~ i k 0
        ~ < k n { ( vec_set [f] . wv data k ( _mlp_fget src + off k ) ) = k + k 1 }
        = off + off n
        = l + l 1
    }
    = l 0
    ~ < l nl {
        : GVar bl ?? ( vec_get [GVar] bs l ) { T x → x F → @ GVar { -1 } }
        : Tensor bv ( gvar_value tp bl )
        : i n ( vec_len [f] . bv data )
        : ~ i k 0
        ~ < k n { ( vec_set [f] . bv data k ( _mlp_fget src + off k ) ) = k + k 1 }
        = off + off n
        = l + l 1
    }
}

// mlp_train's recipe, grad engine. Updates `m` in place, returns the report.
@ mlp_train_grad Mlp m ( Vec f ) X i n i d ( Vec f ) Y i dout MlpCfg cfg → MlpTrain {
    : Rng g ( rng_seed . cfg seed )
    : i nl . m n_layers
    // One shuffled split: [0, n_train) train, [n_train, n) validation.
    : ( Vec i ) idx ( vec_iota 0 n )
    : ~ i k0 0
    ~ < k0 - n 1 {
        : i j0 + k0 ( rng_below g - n k0 )
        ( vec_swap [i] idx k0 j0 )
        = k0 + k0 1
    }
    : ~ i n_val 0
    ? . cfg early_stop {
        = n_val # i ( round * . cfg val_frac # f n )
        ? < n_val 1 { = n_val 1 } {}
        ? >= n_val n { = n_val / n 5 } {}
    } {}
    : i n_train - n n_val
    : ~ i bsz . cfg batch
    ? <= bsz 0 { = bsz 200 } {}
    ? > bsz n_train { = bsz n_train } {}
    // The tape: parameters (and the fixed validation batch) live below the
    // mark; every episode above it is dropped by tape_reset_to.
    : *GTape tp ( tape_new )
    : ( Vec GVar ) ws ( vec_new [GVar] )
    : ( Vec GVar ) bs2 ( vec_new [GVar] )
    : ~ i l 0
    ~ < l nl {
        ( vec_push [GVar] ws ( _gf_wparam tp m l ) )
        ( vec_push [GVar] bs2 ( _gf_bparam tp m l ) )
        = l + l 1
    }
    : *Opt o ( opt_adam_new . cfg lr )
    = l 0
    ~ < l nl {
        ( opt_add o tp ?? ( vec_get [GVar] ws l ) { T x → x F → @ GVar { -1 } } 0.0 )
        ( opt_add o tp ?? ( vec_get [GVar] bs2 l ) { T x → x F → @ GVar { -1 } } 0.0 )
        = l + l 1
    }
    : ~ GVar vx @ GVar { -1 }
    : ~ GVar vy @ GVar { -1 }
    ? & . cfg early_stop > n_val 0 {
        = vx ( _gf_rows_const tp X d idx n_train n )
        = vy ( _gf_rows_const tp Y dout idx n_train n )
    } {}
    : i mark ( tape_mark tp )
    : ( Vec f ) best ( vec_new [f] )
    : ~ f bestc 0.0
    : ~ b have_best F
    : ~ i bad 0
    : ~ i epoch 0
    : ~ f train_loss 0.0
    : ~ b stopped F
    ~ & < epoch . cfg max_iter ! stopped {
        // Shuffle the TRAIN region only; the val tail stays fixed.
        : ~ i k 0
        ~ < k - n_train 1 {
            : i j + k ( rng_below g - n_train k )
            ( vec_swap [i] idx k j )
            = k + k 1
        }
        : ~ f se 0.0
        : ~ i at 0
        ~ < at n_train {
            : ~ i bend + at bsz
            ? > bend n_train { = bend n_train } {}
            : i cnt - bend at
            : GVar xb ( _gf_rows_const tp X d idx at bend )
            : GVar yb ( _gf_rows_const tp Y dout idx at bend )
            : GVar yh ( _gf_forward tp xb ws bs2 nl )
            : GVar df ( g_sub tp yh yb )
            : GVar ssq ( g_sum tp ( g_mul tp df df ) )
            // + α·Σ‖W‖² (weights only), then /(2·B): dL/dW == (Σδa + αW)/B
            : ~ GVar reg ssq
            ? > . cfg alpha 0.0 {
                : ~ GVar l2 @ GVar { -1 }
                : ~ i l3 0
                ~ < l3 nl {
                    : GVar wl ?? ( vec_get [GVar] ws l3 ) { T x → x F → @ GVar { -1 } }
                    : GVar sq ( g_sum tp ( g_mul tp wl wl ) )
                    ? < . l2 id 0 { = l2 sq } { = l2 ( g_add tp l2 sq ) }
                    = l3 + l3 1
                }
                = reg ( g_add tp ssq ( g_muls tp l2 . cfg alpha ) )
            } {}
            : GVar loss ( g_muls tp reg / 1.0 * 2.0 # f cnt )
            : b _bk ( backward tp loss )
            = se + se ( g_scalar tp ssq )
            ( opt_step o tp )
            ( tape_reset_to tp mark )
            = at bend
        }
        = train_loss / se # f * n_train dout
        : ~ f crit train_loss
        ? & . cfg early_stop > n_val 0 {
            : GVar vh ( _gf_forward tp vx ws bs2 nl )
            : GVar vm ( g_mse tp vh vy )
            = crit ( g_scalar tp vm )
            ( tape_reset_to tp mark )
        } {}
        ? . cfg verbose {
            ( nurl_print `epoch ` ) ( nurl_print_int + epoch 1 )
            ( nurl_print ` train_mse ` ) ( nurl_print ( nurl_str_float train_loss ) )
            ( nurl_print ` crit ` ) ( nurl_print ( nurl_str_float crit ) )
            ( nurl_print `\n` )
        } {}
        ? | ! have_best < crit - bestc . cfg tol {
            = bad 0
            ? | ! have_best < crit bestc { = bestc crit } {}
            = have_best T
            ? . cfg early_stop { ( _gf_snapshot tp ws bs2 nl best ) } {}
        } {
            = bad + bad 1
            ? >= bad . cfg n_no_change { = stopped T } {}
        }
        = epoch + epoch 1
    }
    ? & . cfg early_stop have_best { ( _gf_restore tp ws bs2 nl best ) } {}
    ( _gf_write_back m tp ws bs2 nl )
    ( vec_free [f] best )
    ( vec_free [GVar] ws ) ( vec_free [GVar] bs2 )
    ( opt_free o ) ( tape_free tp )
    ( vec_free [i] idx ) ( rng_free g )
    ^ @ MlpTrain { epoch train_loss bestc stopped }
}

// mlp_fit's restart selection, grad engine.
@ mlp_fit_grad ( Vec i ) sizes ( Vec f ) X i n i d ( Vec f ) Y i dout MlpCfg cfg i restarts → MlpFit {
    : ~ i r2 restarts
    ? < r2 1 { = r2 1 } {}
    : ~ Mlp best_m ( mlp_new sizes . cfg seed )
    : ~ MlpTrain best_tr ( mlp_train_grad best_m X n d Y dout cfg )
    : ~ i r 1
    ~ < r r2 {
        : ~ MlpCfg c cfg
        = . c seed + . cfg seed r
        : Mlp m ( mlp_new sizes . c seed )
        : MlpTrain tr ( mlp_train_grad m X n d Y dout c )
        ? < . tr best_val . best_tr best_val {
            ( mlp_free best_m )
            = best_m m
            = best_tr tr
        } {
            ( mlp_free m )
        }
        = r + r 1
    }
    ^ @ MlpFit { best_m best_tr }
}

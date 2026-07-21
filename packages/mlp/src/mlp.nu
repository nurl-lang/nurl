// mlp — a trainable multi-layer perceptron in pure NURL.
//
// Dense layers with ReLU hidden activations and a linear output, trained
// with minibatch Adam on squared loss — the same recipe as sklearn's
// MLPRegressor, and deliberately faithful to it:
//
//   * Glorot uniform init: W, b ~ U(−√(6/(fan_in+fan_out)), +√(…)),
//     drawn from a seedable PRNG (std/rng) — a fixed seed gives the same
//     network on every platform.
//   * squared loss with L2: grad = (AᵀΔ + α·W) / B per batch of B.
//   * Adam with bias correction: lr_t = lr·√(1−β2ᵗ)/(1−β1ᵗ).
//   * batch_size = min(200, n) — sklearn's "auto".
//   * early stopping: a validation split (val_frac) is held out once,
//     the epoch loop stops after n_no_change epochs without the
//     validation MSE improving by > tol, and the BEST weights seen are
//     restored (not the last). With early_stop off the same patience
//     applies to the training loss, mirroring sklearn. (sklearn scores
//     R² on the validation set; for a fixed split maximising R² is
//     minimising MSE, so the criterion is the same up to tol's scale.)
//
// An autoencoder is just ( mlp_train m X n d X d cfg ) — input as target.
//
// Layout: one flat weight buffer + one flat bias buffer for the whole
// network (struct-of-arrays, like iforest's node arena). Layer l maps
// sizes[l] → sizes[l+1]; its weights are row-major n_out×n_in at
// w_off[l], its biases at b_off[l]. Hot loops read through raw pointers
// (vec_data) and write with vec_set — the fft.nu idiom.
//
// Persistence: mlp_save/mlp_load round-trip through JSON with every f64
// stored as its bit pattern (i64) — exact, platform-independent restore
// (nurl_str_float renders ~6 significant digits, so decimal text would
// silently perturb a trained model).

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/rng.nu`
$ `stdlib/ext/json.nu`

// ── Types ─────────────────────────────────────────────────────────────

: Mlp {
    i n_layers  // weight layers = len(sizes) − 1
    ( Vec i ) sizes  // neuron counts, input first, output last
    ( Vec i ) w_off  // offset of layer l's weights in `w`
    ( Vec i ) b_off  // offset of layer l's biases in `b`
    ( Vec i ) a_off  // offset of layer l's activations in a scratch
    i n_w  // total weight count
    i n_b  // total bias count
    i n_a  // total activation count (all layers, one sample)
    ( Vec f ) w
    ( Vec f ) b
    // Adam state, same shapes as w / b
    ( Vec f ) mw
    ( Vec f ) vw
    ( Vec f ) mb
    ( Vec f ) vb
}

: MlpCfg {
    f lr  // Adam initial learning rate (sklearn: 0.001)
    f alpha  // L2 penalty (sklearn: 0.0001)
    i max_iter  // epochs (sklearn: 200; sklearn AE recipes use 500)
    i batch  // minibatch size; 0 = min(200, n) ("auto")
    b early_stop  // hold out a validation split and stop on plateau
    f val_frac  // validation fraction (sklearn: 0.1)
    i n_no_change  // patience in epochs (sklearn: 10)
    f tol  // minimum improvement (sklearn: 1e-4)
    i seed  // PRNG seed (init + shuffles + the val split)
    b verbose  // print per-epoch losses
}

// What mlp_train reports back.
: MlpTrain {
    i n_iter  // epochs actually run
    f loss  // final training MSE (plain mean squared error)
    f best_val  // best validation MSE (early_stop) or best train MSE
    b stopped_early  // the patience tripped before max_iter
}

// Min–max scaler: x' = (x − lo) / (hi − lo), zero-range columns → 0.
: MinMax {
    i n_cols
    ( Vec f ) lo
    ( Vec f ) hi
}

// ── Small helpers ─────────────────────────────────────────────────────

@ __zeros i n → ( Vec f ) {
    : ( Vec f ) v ( vec_with_cap [f] n )
    : ~ i k 0
    ~ < k n { ( vec_push [f] v 0.0 ) = k + k 1 }
    ^ v
}

@ _mlp_fget ( Vec f ) v i idx → f {
    ^ ?? ( vec_get [f] v idx ) { T x → x F → 0.0 }
}

@ _mlp_iget ( Vec i ) v i idx → i {
    ^ ?? ( vec_get [i] v idx ) { T x → x F → 0 }
}

// Fisher–Yates shuffle of an index vector (seeded, deterministic).
@ __shuffle ( Vec i ) idx Rng g → v {
    : i n ( vec_len [i] idx )
    : ~ i k 0
    ~ < k - n 1 {
        : i j + k ( rng_below g - n k )
        ( vec_swap [i] idx k j )
        = k + k 1
    }
}

// ── Construction ──────────────────────────────────────────────────────

// A fresh network with Glorot-uniform weights. `sizes` lists every layer
// width, input first (e.g. [8 64 32 64 8] for the classic autoencoder);
// the caller keeps ownership of `sizes` (it is copied).
@ mlp_new ( Vec i ) sizes i seed → Mlp {
    : i nl - ( vec_len [i] sizes ) 1
    : ( Vec i ) sz ( vec_new [i] )
    : ~ i c 0
    ~ < c + nl 1 { ( vec_push [i] sz ( _mlp_iget sizes c ) ) = c + c 1 }
    : ( Vec i ) woff ( vec_new [i] )
    : ( Vec i ) boff ( vec_new [i] )
    : ( Vec i ) aoff ( vec_new [i] )
    : ~ i nw 0
    : ~ i nb 0
    : ~ i na 0
    : ~ i l 0
    ~ < l nl {
        ( vec_push [i] woff nw )
        ( vec_push [i] boff nb )
        ( vec_push [i] aoff na )
        = nw + nw * ( _mlp_iget sz l ) ( _mlp_iget sz + l 1 )
        = nb + nb ( _mlp_iget sz + l 1 )
        = na + na ( _mlp_iget sz l )
        = l + l 1
    }
    ( vec_push [i] aoff na )  // a_off[nl] = output activations
    = na + na ( _mlp_iget sz nl )
    : Rng g ( rng_seed seed )
    : ( Vec f ) w ( vec_with_cap [f] nw )
    : ( Vec f ) b ( vec_with_cap [f] nb )
    = l 0
    ~ < l nl {
        : i fin ( _mlp_iget sz l )
        : i fout ( _mlp_iget sz + l 1 )
        : f bound ( sqrt / 6.0 # f + fin fout )
        : ~ i k 0
        ~ < k * fin fout {
            ( vec_push [f] w - * 2.0 * bound ( rng_u01 g ) bound )
            = k + k 1
        }
        = k 0
        ~ < k fout {
            ( vec_push [f] b - * 2.0 * bound ( rng_u01 g ) bound )
            = k + k 1
        }
        = l + l 1
    }
    ( rng_free g )
    ^ @ Mlp { nl sz woff boff aoff nw nb na w b
        ( __zeros nw ) ( __zeros nw ) ( __zeros nb ) ( __zeros nb ) }
}

@ mlp_cfg_default → MlpCfg {
    ^ @ MlpCfg { 0.001 0.0001 500 0 T 0.1 10 0.0001 42 F }
}

@ mlp_free Mlp m → v {
    ( vec_free [i] . m sizes )
    ( vec_free [i] . m w_off )
    ( vec_free [i] . m b_off )
    ( vec_free [i] . m a_off )
    ( vec_free [f] . m w )
    ( vec_free [f] . m b )
    ( vec_free [f] . m mw )
    ( vec_free [f] . m vw )
    ( vec_free [f] . m mb )
    ( vec_free [f] . m vb )
}

// ── Forward pass ──────────────────────────────────────────────────────

// One sample: read d input values at xp[x_at..], fill the activation
// scratch `acts` (length n_a). Hidden layers ReLU, output linear.
@ __mlp_forward Mlp m * f xp i x_at ( Vec f ) acts → v {
    : *i szp ( vec_data [i] . m sizes )
    : *i wop ( vec_data [i] . m w_off )
    : *i bop ( vec_data [i] . m b_off )
    : *i aop ( vec_data [i] . m a_off )
    : *f wp ( vec_data [f] . m w )
    : *f bp ( vec_data [f] . m b )
    : i din . szp 0
    : ~ i c 0
    ~ < c din { ( vec_set [f] acts c . xp + x_at c ) = c + c 1 }
    : ~ i l 0
    ~ < l . m n_layers {
        : i fin . szp l
        : i fout . szp + l 1
        : i wo . wop l
        : i bo . bop l
        : i ai . aop l
        : i ao . aop + l 1
        : b last == l - . m n_layers 1
        : *f ap ( vec_data [f] acts )
        : ~ i j 0
        ~ < j fout {
            : ~ f z . bp + bo j
            : i wrow + wo * j fin
            : ~ i i2 0
            ~ < i2 fin {
                = z + z * . wp + wrow i2 . ap + ai i2
                = i2 + i2 1
            }
            ? & ! last < z 0.0 { = z 0.0 } {}
            ( vec_set [f] acts + ao j z )
            = j + j 1
        }
        = l + l 1
    }
}

// Predict one row (a ( Vec f ) of the input width) → an OWNED output vec.
@ mlp_predict Mlp m ( Vec f ) x → ( Vec f ) {
    : ( Vec f ) acts ( __zeros . m n_a )
    ( __mlp_forward m ( vec_data [f] x ) 0 acts )
    : i dout ( _mlp_iget . m sizes . m n_layers )
    : i oa ( _mlp_iget . m a_off . m n_layers )
    : ( Vec f ) out ( vec_with_cap [f] dout )
    : ~ i k 0
    ~ < k dout { ( vec_push [f] out ( _mlp_fget acts + oa k ) ) = k + k 1 }
    ( vec_free [f] acts )
    ^ out
}

// Mean squared error of the network over rows X (n×d row-major) against
// targets Y (n×dout row-major): mean over every output element.
@ mlp_mse Mlp m ( Vec f ) X i n i d ( Vec f ) Y → f {
    ? == n 0 { ^ 0.0 } {}
    : ( Vec f ) acts ( __zeros . m n_a )
    : *f xp ( vec_data [f] X )
    : *f yp ( vec_data [f] Y )
    : i dout ( _mlp_iget . m sizes . m n_layers )
    : i oa ( _mlp_iget . m a_off . m n_layers )
    : ~ f se 0.0
    : ~ i r 0
    ~ < r n {
        ( __mlp_forward m xp * r d acts )
        : *f ap ( vec_data [f] acts )
        : ~ i j 0
        ~ < j dout {
            : f e - . ap + oa j . yp + * r dout j
            = se + se * e e
            = j + j 1
        }
        = r + r 1
    }
    ( vec_free [f] acts )
    ^ / se # f * n dout
}

// ── Training ──────────────────────────────────────────────────────────

// Accumulate one sample's gradient into gw / gb. `acts` must hold the
// sample's forward pass; `deltas` is a scratch of n_a (layer-aligned like
// acts). Returns nothing; the batch divide + L2 happen in the Adam step.
@ __mlp_backprop Mlp m ( Vec f ) acts * f yp i y_at ( Vec f ) deltas ( Vec f ) gw ( Vec f ) gb → v {
    : *i szp ( vec_data [i] . m sizes )
    : *i wop ( vec_data [i] . m w_off )
    : *i bop ( vec_data [i] . m b_off )
    : *i aop ( vec_data [i] . m a_off )
    : *f wp ( vec_data [f] . m w )
    : *f ap ( vec_data [f] acts )
    : i nl . m n_layers
    : i dout . szp nl
    : i oa . aop nl
    // δ_out = ŷ − y  (squared loss, linear output)
    : ~ i j 0
    ~ < j dout {
        ( vec_set [f] deltas + oa j - . ap + oa j . yp + y_at j )
        = j + j 1
    }
    : ~ i l - nl 1
    ~ >= l 0 {
        : i fin . szp l
        : i fout . szp + l 1
        : i wo . wop l
        : i bo . bop l
        : i ai . aop l
        : i ao . aop + l 1
        : *f dp ( vec_data [f] deltas )
        // gw += δ_{l+1} ⊗ a_l ; gb += δ_{l+1}
        = j 0
        ~ < j fout {
            : f dj . dp + ao j
            : i wrow + wo * j fin
            : ~ i i2 0
            ~ < i2 fin {
                : i o + wrow i2
                ( vec_set [f] gw o + ( _mlp_fget gw o ) * dj . ap + ai i2 )
                = i2 + i2 1
            }
            : i ob + bo j
            ( vec_set [f] gb ob + ( _mlp_fget gb ob ) dj )
            = j + j 1
        }
        // δ_l = (Wᵀ δ_{l+1}) ⊙ relu'(a_l) — the input layer needs none.
        ? > l 0 {
            : ~ i i3 0
            ~ < i3 fin {
                : ~ f s 0.0
                : ~ i j2 0
                ~ < j2 fout {
                    = s + s * . wp + + wo * j2 fin i3 . dp + ao j2
                    = j2 + j2 1
                }
                ? <= . ap + ai i3 0.0 { = s 0.0 } {}
                ( vec_set [f] deltas + ai i3 s )
                = i3 + i3 1
            }
        } {}
        = l - l 1
    }
}

// One Adam update from gradient sums over a batch of `bsz` samples:
// g = (Σg + α·param) / bsz for weights (sklearn adds the L2 term before
// the batch divide), g = Σg / bsz for biases. Zeroes gw / gb after.
// `tstep` is the 1-based Adam step count, owned by mlp_train: NURL structs
// pass by value (only their Vec fields alias), so a counter FIELD on Mlp
// could never advance across calls — it silently froze the bias correction
// at t = 1 for every batch after the first.
@ __mlp_adam Mlp m ( Vec f ) gw ( Vec f ) gb i bsz f lr f alpha i tstep → v {
    : f t # f tstep
    : f b1 0.9
    : f b2 0.999
    : f eps 0.00000001
    : f lrt * lr / ( sqrt - 1.0 ( pow b2 t ) ) - 1.0 ( pow b1 t )
    : f fb # f bsz
    : *f wp ( vec_data [f] . m w )
    : *f gwp ( vec_data [f] gw )
    : ~ i k 0
    ~ < k . m n_w {
        : f g / + . gwp k * alpha . wp k fb
        : f nm + * b1 ( _mlp_fget . m mw k ) * - 1.0 b1 g
        : f nv + * b2 ( _mlp_fget . m vw k ) * - 1.0 b2 * g g
        ( vec_set [f] . m mw k nm )
        ( vec_set [f] . m vw k nv )
        ( vec_set [f] . m w k - . wp k / * lrt nm + ( sqrt nv ) eps )
        ( vec_set [f] gw k 0.0 )
        = k + k 1
    }
    : *f bp ( vec_data [f] . m b )
    : *f gbp ( vec_data [f] gb )
    = k 0
    ~ < k . m n_b {
        : f g / . gbp k fb
        : f nm + * b1 ( _mlp_fget . m mb k ) * - 1.0 b1 g
        : f nv + * b2 ( _mlp_fget . m vb k ) * - 1.0 b2 * g g
        ( vec_set [f] . m mb k nm )
        ( vec_set [f] . m vb k nv )
        ( vec_set [f] . m b k - . bp k / * lrt nm + ( sqrt nv ) eps )
        ( vec_set [f] gb k 0.0 )
        = k + k 1
    }
}

// MSE over a subset of rows given by idx[from..to) — the validation view.
@ __mlp_mse_idx Mlp m * f xp i d * f yp i dout ( Vec i ) idx i from i to ( Vec f ) acts → f {
    ? <= to from { ^ 0.0 } {}
    : i oa ( _mlp_iget . m a_off . m n_layers )
    : ~ f se 0.0
    : ~ i k from
    ~ < k to {
        : i r ( _mlp_iget idx k )
        ( __mlp_forward m xp * r d acts )
        : *f ap ( vec_data [f] acts )
        : ~ i j 0
        ~ < j dout {
            : f e - . ap + oa j . yp + * r dout j
            = se + se * e e
            = j + j 1
        }
        = k + k 1
    }
    ^ / se # f * - to from dout
}

// Train on X (n×d, row-major) against Y (n×dout). For an autoencoder pass
// X for Y and d for dout. Returns the training report; the model is
// updated in place (best-validation weights when early_stop is on).
@ mlp_train Mlp m ( Vec f ) X i n i d ( Vec f ) Y i dout MlpCfg cfg → MlpTrain {
    : Rng g ( rng_seed . cfg seed )
    : *f xp ( vec_data [f] X )
    : *f yp ( vec_data [f] Y )
    : ( Vec f ) acts ( __zeros . m n_a )
    : ( Vec f ) deltas ( __zeros . m n_a )
    : ( Vec f ) gw ( __zeros . m n_w )
    : ( Vec f ) gb ( __zeros . m n_b )
    // One shuffled split: [0, n_train) train, [n_train, n) validation.
    : ( Vec i ) idx ( vec_iota 0 n )
    ( __shuffle idx g )
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
    // Best-weights snapshot for the early-stopping restore.
    : ( Vec f ) best_w ( __zeros . m n_w )
    : ( Vec f ) best_b ( __zeros . m n_b )
    : ~ f best 0.0
    : ~ b have_best F
    : ~ i bad 0
    : ~ i epoch 0
    : ~ f train_loss 0.0
    : ~ b stopped F
    : ~ i adam_t 0  // Adam step count (see __mlp_adam)
    ~ & < epoch . cfg max_iter ! stopped {
        // Shuffle the TRAIN region only; the val tail stays fixed.
        : ~ i k 0
        ~ < k - n_train 1 {
            : i j + k ( rng_below g - n_train k )
            ( vec_swap [i] idx k j )
            = k + k 1
        }
        // Minibatch pass.
        : ~ f se 0.0
        : i oa ( _mlp_iget . m a_off . m n_layers )
        : ~ i at 0
        ~ < at n_train {
            : ~ i bend + at bsz
            ? > bend n_train { = bend n_train } {}
            : ~ i s at
            ~ < s bend {
                : i r ( _mlp_iget idx s )
                ( __mlp_forward m xp * r d acts )
                : *f ap ( vec_data [f] acts )
                : ~ i j 0
                ~ < j dout {
                    : f e - . ap + oa j . yp + * r dout j
                    = se + se * e e
                    = j + j 1
                }
                ( __mlp_backprop m acts yp * r dout deltas gw gb )
                = s + s 1
            }
            = adam_t + adam_t 1
            ( __mlp_adam m gw gb - bend at . cfg lr . cfg alpha adam_t )
            = at bend
        }
        = train_loss / se # f * n_train dout
        // The plateau criterion: validation MSE with early_stop, else the
        // training loss (sklearn's non-early-stopping path).
        : ~ f crit train_loss
        ? . cfg early_stop {
            = crit ( __mlp_mse_idx m xp d yp dout idx n_train n acts )
        } {}
        ? . cfg verbose {
            ( nurl_print `epoch ` ) ( nurl_print_int + epoch 1 )
            ( nurl_print ` train_mse ` ) ( nurl_print ( nurl_str_float train_loss ) )
            ( nurl_print ` crit ` ) ( nurl_print ( nurl_str_float crit ) )
            ( nurl_print `\n` )
        } {}
        ? | ! have_best < crit - best . cfg tol {
            = bad 0
            ? | ! have_best < crit best { = best crit } {}
            = have_best T
            ? . cfg early_stop {
                : ~ i c2 0
                ~ < c2 . m n_w { ( vec_set [f] best_w c2 ( _mlp_fget . m w c2 ) ) = c2 + c2 1 }
                = c2 0
                ~ < c2 . m n_b { ( vec_set [f] best_b c2 ( _mlp_fget . m b c2 ) ) = c2 + c2 1 }
            } {}
        } {
            = bad + bad 1
            ? >= bad . cfg n_no_change { = stopped T } {}
        }
        = epoch + epoch 1
    }
    // Restore the best weights (early stopping keeps the best epoch, not
    // the last — sklearn does the same).
    ? & . cfg early_stop have_best {
        : ~ i c3 0
        ~ < c3 . m n_w { ( vec_set [f] . m w c3 ( _mlp_fget best_w c3 ) ) = c3 + c3 1 }
        = c3 0
        ~ < c3 . m n_b { ( vec_set [f] . m b c3 ( _mlp_fget best_b c3 ) ) = c3 + c3 1 }
    } {}
    ( vec_free [f] best_w )
    ( vec_free [f] best_b )
    ( vec_free [f] acts )
    ( vec_free [f] deltas )
    ( vec_free [f] gw )
    ( vec_free [f] gb )
    ( vec_free [i] idx )
    ( rng_free g )
    ^ @ MlpTrain { epoch train_loss best stopped }
}

// ── Restarts: train several inits, keep the best ──────────────────────
//
// A narrow ReLU bottleneck can die at init (every pre-activation negative
// → the layer collapses and the net predicts the mean; the training MSE
// plateaus at the data variance). sklearn has the same failure mode and
// leaves the retry to the user. mlp_fit makes it a deterministic feature:
// train `restarts` networks with seeds cfg.seed, cfg.seed+1, …, and keep
// the one with the best plateau criterion (validation MSE under
// early_stop, training MSE otherwise). restarts ≤ 1 trains exactly once.

: MlpFit {
    Mlp model
    MlpTrain report
}

@ mlp_fit ( Vec i ) sizes ( Vec f ) X i n i d ( Vec f ) Y i dout MlpCfg cfg i restarts → MlpFit {
    : ~ i r2 restarts
    ? < r2 1 { = r2 1 } {}
    // First candidate trains the returned network directly.
    : ~ Mlp best_m ( mlp_new sizes . cfg seed )
    : ~ MlpTrain best_tr ( mlp_train best_m X n d Y dout cfg )
    : ~ i r 1
    ~ < r r2 {
        : ~ MlpCfg c cfg
        = . c seed + . cfg seed r
        : Mlp m ( mlp_new sizes . c seed )
        : MlpTrain tr ( mlp_train m X n d Y dout c )
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

// ── Persistence (bit-exact JSON) ──────────────────────────────────────

@ __floats_to_bits_json ( Vec f ) v → Json {
    : Json a ( json_arr_new )
    : i n ( vec_len [f] v )
    : ~ i k 0
    ~ < k n {
        ( json_arr_push a ( json_int ( f64_to_bits ( _mlp_fget v k ) ) ) )
        = k + k 1
    }
    ^ a
}

@ __bits_json_to_floats Json a → ( Vec f ) {
    : i n ( json_arr_len a )
    : ( Vec f ) v ( vec_with_cap [f] n )
    : ~ i k 0
    ~ < k n {
        : f x ?? ( json_arr_get a k ) {
            T e → ( bits_to_f64 ?? ( json_num_as_i e ) { T b → b F → 0 } )
            F → 0.0
        }
        ( vec_push [f] v x )
        = k + k 1
    }
    ^ v
}

@ __ints_json ( Vec i ) v → Json {
    : Json a ( json_arr_new )
    : i n ( vec_len [i] v )
    : ~ i k 0
    ~ < k n { ( json_arr_push a ( json_int ( _mlp_iget v k ) ) ) = k + k 1 }
    ^ a
}

@ __json_ints Json a → ( Vec i ) {
    : i n ( json_arr_len a )
    : ( Vec i ) v ( vec_with_cap [i] n )
    : ~ i k 0
    ~ < k n {
        ( vec_push [i] v ?? ( json_arr_get a k ) {
            T e → ?? ( json_num_as_i e ) { T x → x F → 0 }
            F → 0 } )
        = k + k 1
    }
    ^ v
}

// Serialise the trained network (weights + biases; Adam state is NOT
// persisted — a loaded model predicts, or fine-tunes from a fresh
// optimiser). Returns an OWNED String of JSON.
@ mlp_save Mlp m → String {
    : Json o ( json_obj_new )
    ( json_obj_set o `sizes` ( __ints_json . m sizes ) )
    ( json_obj_set o `w` ( __floats_to_bits_json . m w ) )
    ( json_obj_set o `b` ( __floats_to_bits_json . m b ) )
    : String s ( json_stringify o )
    ( json_free o )
    ^ s
}

// Rebuild a network from mlp_save output. F on malformed input.
@ mlp_load s src → ?Mlp {
    ?? ( json_parse src ) {
        F _ → { ^ @ ?Mlp { F } }
        T root → {
            : ?Json szj ( json_obj_get root `sizes` )
            : ?Json wj ( json_obj_get root `w` )
            : ?Json bj ( json_obj_get root `b` )
            : ~ b ok T
            ? ?? szj { T _ → F F → T } { = ok F } {}
            ? ?? wj { T _ → F F → T } { = ok F } {}
            ? ?? bj { T _ → F F → T } { = ok F } {}
            ? ! ok { ( json_free root ) ^ @ ?Mlp { F } } {}
            : ( Vec i ) sizes ?? szj { T j → ( __json_ints j ) F → ( vec_new [i] ) }
            ? < ( vec_len [i] sizes ) 2 {
                ( vec_free [i] sizes ) ( json_free root ) ^ @ ?Mlp { F }
            } {}
            : Mlp m ( mlp_new sizes 0 )
            ( vec_free [i] sizes )
            : ( Vec f ) w ?? wj { T j → ( __bits_json_to_floats j ) F → ( vec_new [f] ) }
            : ( Vec f ) b ?? bj { T j → ( __bits_json_to_floats j ) F → ( vec_new [f] ) }
            ? & == ( vec_len [f] w ) . m n_w == ( vec_len [f] b ) . m n_b {
                : ~ i k 0
                ~ < k . m n_w { ( vec_set [f] . m w k ( _mlp_fget w k ) ) = k + k 1 }
                = k 0
                ~ < k . m n_b { ( vec_set [f] . m b k ( _mlp_fget b k ) ) = k + k 1 }
                ( vec_free [f] w ) ( vec_free [f] b ) ( json_free root )
                ^ @ ?Mlp { T m }
            } {
                ( vec_free [f] w ) ( vec_free [f] b ) ( json_free root )
                ( mlp_free m )
                ^ @ ?Mlp { F }
            }
        }
    }
}

// ── MinMax scaler ─────────────────────────────────────────────────────

@ minmax_fit ( Vec f ) X i n i d → MinMax {
    : ( Vec f ) lo ( __zeros d )
    : ( Vec f ) hi ( __zeros d )
    : *f xp ( vec_data [f] X )
    : ~ i c 0
    ~ < c d {
        : ~ f mn 0.0
        : ~ f mx 0.0
        ? > n 0 { = mn . xp c = mx . xp c } {}
        : ~ i r 1
        ~ < r n {
            : f v . xp + * r d c
            ? < v mn { = mn v } {}
            ? > v mx { = mx v } {}
            = r + r 1
        }
        ( vec_set [f] lo c mn )
        ( vec_set [f] hi c mx )
        = c + c 1
    }
    ^ @ MinMax { d lo hi }
}

// Scale rows in place: x' = (x − lo) / (hi − lo); zero-range columns → 0.
@ minmax_apply MinMax mm ( Vec f ) X i n → v {
    : i d . mm n_cols
    : *f lop ( vec_data [f] . mm lo )
    : *f hip ( vec_data [f] . mm hi )
    : *f xp ( vec_data [f] X )
    : ~ i r 0
    ~ < r n {
        : ~ i c 0
        ~ < c d {
            : i o + * r d c
            : f range - . hip c . lop c
            : f v ? == range 0.0 0.0 / - . xp o . lop c range
            ( vec_set [f] X o v )
            = c + c 1
        }
        = r + r 1
    }
}

@ minmax_save MinMax mm → String {
    : Json o ( json_obj_new )
    ( json_obj_set o `n_cols` ( json_int . mm n_cols ) )
    ( json_obj_set o `lo` ( __floats_to_bits_json . mm lo ) )
    ( json_obj_set o `hi` ( __floats_to_bits_json . mm hi ) )
    : String s ( json_stringify o )
    ( json_free o )
    ^ s
}

@ minmax_load s src → ?MinMax {
    ?? ( json_parse src ) {
        F _ → { ^ @ ?MinMax { F } }
        T root → {
            : i d ?? ( json_obj_get root `n_cols` ) { T j → ( json_as_int j ) F → 0 }
            : ( Vec f ) lo ?? ( json_obj_get root `lo` ) { T j → ( __bits_json_to_floats j ) F → ( vec_new [f] ) }
            : ( Vec f ) hi ?? ( json_obj_get root `hi` ) { T j → ( __bits_json_to_floats j ) F → ( vec_new [f] ) }
            ( json_free root )
            ? & & > d 0 == ( vec_len [f] lo ) d == ( vec_len [f] hi ) d {
                ^ @ ?MinMax { T @ MinMax { d lo hi } }
            } {
                ( vec_free [f] lo ) ( vec_free [f] hi )
                ^ @ ?MinMax { F }
            }
        }
    }
}

@ minmax_free MinMax mm → v {
    ( vec_free [f] . mm lo )
    ( vec_free [f] . mm hi )
}
